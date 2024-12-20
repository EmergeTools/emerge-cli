require 'dry/cli'
require 'json'
require 'uri'
require 'chunky_png'
require 'async'
require 'async/barrier'
require 'async/semaphore'
require 'async/http/internet/instance'

module EmergeCLI
  module Commands
    module Upload
      class Snapshots < EmergeCLI::Commands::GlobalOptions
        desc 'Upload snapshot images to Emerge'

        option :id, type: :string, required: true, desc: 'Unique identifier to group runs together'
        option :name, type: :string, required: true, desc: 'Name of the run'

        # Optional options
        option :api_token, type: :string, required: false,
                           desc: 'API token for authentication, defaults to ENV[EMERGE_API_TOKEN]'
        option :sha, type: :string, required: false, desc: 'SHA of the commit'
        option :branch, type: :string, required: false, desc: 'Branch name'
        option :repo_name, type: :string, required: false, desc: 'Repository name'
        option :base_sha, type: :string, required: false, desc: 'Base SHA'
        option :previous_sha, type: :string, required: false, desc: 'Previous SHA'
        option :pr_number, type: :string, required: false, desc: 'PR number'
        option :concurrency, type: :integer, default: 5, desc: 'Number of concurrency for parallel uploads'

        option :client_library, type: :string, required: false, values: %w[swift-snapshot-testing paparazzi roborazzi],
                                desc: 'Client library used for snapshots'
        option :project_root, type: :string, required: false, desc: 'Path to the project root'

        option :profile, type: :boolean, default: false, desc: 'Enable performance profiling metrics'

        argument :image_paths, type: :array, required: false, desc: 'Paths to folders containing images'

        def initialize(network: nil, git_info_provider: nil)
          @network = network
          @git_info_provider = git_info_provider
          @profiler = EmergeCLI::Profiler.new
        end

        def call(image_paths:, **options)
          @options = options
          @profiler = EmergeCLI::Profiler.new(enabled: options[:profile])
          before(options)

          start_time = Time.now
          run_id = nil
          success = false

          begin
            api_token = @options[:api_token] || ENV.fetch('EMERGE_API_TOKEN', nil)
            raise 'API token is required and cannot be blank' if api_token.nil? || api_token.strip.empty?

            @network ||= EmergeCLI::Network.new(api_token:)
            @git_info_provider ||= GitInfoProvider.new

            Sync do
              validate_options(image_paths)

              client = create_client(image_paths)

              image_files = @profiler.measure('find_image_files') { find_image_files(client) }

              @profiler.measure('check_duplicate_files') { check_duplicate_files(image_files, client) }

              run_id = @profiler.measure('create_run') { create_run }

              upload_images(run_id, options[:concurrency], image_files, client)

              @profiler.measure('finish_run') { finish_run(run_id) }
            end

            Logger.info 'Upload completed successfully!'
            Logger.info "Time taken: #{(Time.now - start_time).round(2)} seconds"
            @profiler.report
            Logger.info "✅ View your snapshots at https://emergetools.com/snapshot/#{run_id}"
            success = true
          rescue StandardError => e
            Logger.error "CLI Error: #{e.message}"
            Sync { report_error(run_id, e.message, 'crash') } if run_id
            raise e # Re-raise the error to dry-cli
          ensure
            @network&.close
          end

          success
        end

        private

        def validate_options(image_paths)
          if @options[:client_library] && !@options[:project_root]
            raise 'Project root is required when using a client library'
          end
          if @options[:project_root] && !@options[:client_library]
            raise 'Client library is required when using a project path'
          end
          return unless (@options[:project_root] || @options[:client_library]) && !image_paths.empty?
          raise 'Cannot specify image paths when using a project path or client library'
        end

        def create_client(image_paths)
          if @options[:client_library]
            case @options[:client_library]
            when 'swift-snapshot-testing'
              ClientLibraries::SwiftSnapshotTesting.new(@options[:project_root])
            when 'paparazzi'
              ClientLibraries::Paparazzi.new(@options[:project_root])
            when 'roborazzi'
              ClientLibraries::Roborazzi.new(@options[:project_root])
            else
              raise "Unsupported client library: #{@options[:client_library]}"
            end
          else
            ClientLibraries::Default.new(image_paths)
          end
        end

        def find_image_files(client)
          found_images = client.image_files
          raise 'No images found. Please check your image paths or project configuration.' if found_images.empty?
          Logger.info "Found #{found_images.size} images"
          found_images
        end

        def check_duplicate_files(image_files, client)
          seen_files = {}
          image_files.each do |image_path|
            file_name = client.parse_file_info(image_path)[:file_name]

            if seen_files[file_name]
              Logger.warn "Duplicate file name detected: '#{file_name}'. " \
                          "Previous occurrence: '#{seen_files[file_name]}'. " \
                          'This upload will overwrite the previous one.'
            end
            seen_files[file_name] = image_path
          end
        end

        def create_run
          Logger.info 'Creating run...'

          git_result = @git_info_provider.fetch_git_info

          sha = @options[:sha] || git_result.sha
          branch = @options[:branch] || git_result.branch
          base_sha = @options[:base_sha] || git_result.base_sha
          previous_sha = @options[:previous_sha] || git_result.previous_sha
          pr_number = @options[:pr_number] || git_result.pr_number

          # TODO: Make optional
          raise 'SHA is required' unless sha
          raise 'Branch is required' unless branch
          raise 'Repo name is required' unless @options[:repo_name]

          payload = {
            id: @options[:id],
            name: @options[:name],
            sha:,
            branch:,
            repo_name: @options[:repo_name],
            # Optional
            base_sha:,
            previous_sha:,
            pr_number: pr_number&.to_s
          }.compact

          response = @network.post(path: '/v1/snapshots/run', body: payload)
          run_id = JSON.parse(response.read).fetch('run_id')
          Logger.info "Created run: #{run_id}"

          run_id
        end

        def upload_images(run_id, concurrency, image_files, client)
          Logger.info 'Uploading images...'

          post_image_barrier = Async::Barrier.new
          post_image_semaphore = Async::Semaphore.new(concurrency, parent: post_image_barrier)

          upload_image_barrier = Async::Barrier.new
          upload_image_semaphore = Async::Semaphore.new(concurrency, parent: upload_image_barrier)

          image_files.each_with_index do |image_path, index|
            post_image_semaphore.async do
              Logger.debug "Fetching upload URL for image #{index + 1}/#{image_files.size}: #{image_path}"

              file_info = client.parse_file_info(image_path)

              dimensions = @profiler.measure('chunky_png_processing') do
                datastream = ChunkyPNG::Datastream.from_file(image_path)
                {
                  width: datastream.header_chunk.width,
                  height: datastream.header_chunk.height
                }
              end

              body = {
                run_id:,
                file_name: file_info[:file_name],
                group_name: file_info[:group_name],
                variant_name: file_info[:variant_name],
                width: dimensions[:width],
                height: dimensions[:height]
              }

              upload_url = @profiler.measure('create_image_upload_url') do
                response = @network.post(path: '/v1/snapshots/run/image', body:)
                JSON.parse(response.read).fetch('image_url')
              end

              # Start uploading the image without waiting for it to finish
              upload_image_semaphore.async do
                Logger.info "Uploading image #{index + 1}/#{image_files.size}: #{image_path}"

                @profiler.measure('upload_image') do
                  @network.put(
                    path: upload_url,
                    headers: { 'Content-Type' => 'image/png' },
                    body: File.read(image_path)
                  )
                end
              end
            end
          end

          post_image_barrier.wait
          upload_image_barrier.wait
        ensure
          post_image_barrier&.stop
          upload_image_barrier&.stop
        end

        def finish_run(run_id)
          Logger.info 'Finishing run...'
          @network.post(path: '/v1/snapshots/run/finish', body: { run_id: })
          nil
        end

        def report_error(run_id, error_message, error_code = 'generic')
          @network.post(
            path: '/v1/snapshots/run/error',
            body: {
              run_id:,
              error_code:,
              error_message:
            }
          )
          Logger.info 'Reported error to Emerge'
        rescue StandardError => e
          Logger.error "Failed to report error to Emerge: #{e.message}"
        end
      end
    end
  end
end
