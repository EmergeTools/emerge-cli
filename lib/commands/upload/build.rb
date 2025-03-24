require 'dry/cli'
require 'json'
require 'uri'
require 'async'
require 'async/barrier'
require 'async/semaphore'
require 'async/http/internet/instance'

module EmergeCLI
  module Commands
    module Upload
      class Build < EmergeCLI::Commands::GlobalOptions
        desc 'Upload a build to Emerge'

        option :path, type: :string, required: true, desc: 'Path to the build artifact'

        # Optional options
        option :api_token, type: :string, required: false,
                           desc: 'API token for authentication, defaults to ENV[EMERGE_API_TOKEN]'
        option :sha, type: :string, required: false, desc: 'SHA of the commit'
        option :branch, type: :string, required: false, desc: 'Branch name'
        option :repo_name, type: :string, required: false, desc: 'Repository name'
        option :base_sha, type: :string, required: false, desc: 'Base SHA'
        option :previous_sha, type: :string, required: false, desc: 'Previous SHA'
        option :pr_number, type: :string, required: false, desc: 'PR number'
        option :score, type: :boolean, default: false, required: false, 
               desc: 'Upload build for generating Emerge Score'

        def initialize(network: nil, git_info_provider: nil)
          @network = network
          @git_info_provider = git_info_provider
        end

        def call(**options)
          @options = options
          @profiler = EmergeCLI::Profiler.new(enabled: options[:profile])
          before(options)

          start_time = Time.now

          file_path = options[:path]
          file_exists = File.exist?(file_path)
          raise "File not found at path: #{file_path}" unless file_exists

          file_extension = File.extname(file_path)
          raise "Unsupported file type: #{file_extension}" unless ['.ipa', '.apk', '.aab',
                                                                   '.zip'].include?(file_extension)

          api_token = @options[:api_token] || ENV.fetch('EMERGE_API_TOKEN', nil)
          raise 'API token is required and cannot be blank' if api_token.nil? || api_token.strip.empty?

          @network ||= EmergeCLI::Network.new(api_token:)
          @git_info_provider ||= GitInfoProvider.new

          Sync do
            upload_url, upload_id = fetch_upload_url

            file_size = File.size(file_path)
            Logger.info("Uploading file... (#{file_size} bytes)")

            File.open(file_path, 'rb') do |file|
              headers = {
                'Content-Type' => 'application/zip',
                'Content-Length' => file_size.to_s
              }

              response = @network.put(
                path: upload_url,
                body: file.read,
                headers: headers
              )

              unless response.status == 200
                Logger.error("Upload failed with status #{response.status}")
                Logger.error("Response body: #{response.body}")
                raise "Uploading file failed with status #{response.status}"
              end
            end

            Logger.info('Upload complete successfully!')
            Logger.info "Time taken: #{(Time.now - start_time).round(2)} seconds"
            
            result_url = if @options[:score]
              score_url = "https://emergetools.com/score/#{upload_id}"
              
              Logger.info 'Fetching score...'
              score_response = @network.get(
                path: '/score',
                query: { uploadId: upload_id }
              )
              
              unless score_response.status == 200
                Logger.error("Score calculation trigger failed with status #{score_response.status}")
                Logger.error("Response body: #{score_response.body}")
                raise "Score calculation trigger failed with status #{score_response.status}"
              end
              
              Logger.info '✅ Score calculation triggered'
              score_url
            else
              "https://emergetools.com/build/#{upload_id}"
            end
            
            Logger.info("✅ You can view the #{@options[:score] ? 'score' : 'build analysis'} at #{result_url}")
          end
        end

        private

        def fetch_upload_url
          git_result = @git_info_provider.fetch_git_info
          sha = @options[:sha] || git_result.sha
          branch = @options[:branch] || git_result.branch
          base_sha = @options[:base_sha] || git_result.base_sha
          previous_sha = @options[:previous_sha] || git_result.previous_sha
          pr_number = @options[:pr_number] || git_result.pr_number

          # TODO: Make optional
          raise 'SHA is required' unless sha
          raise 'Branch is required' unless branch

          payload = {
            sha:,
            branch:,
            repo_name: @options[:repo_name],
            # Optional
            base_sha:,
            previous_sha:,
            pr_number: pr_number&.to_s
          }.compact

          upload_response = @network.post(
            path: '/upload',
            body: payload,
            headers: { 'Content-Type' => 'application/json' }
          )
          upload_json = parse_response(upload_response)
          upload_id = upload_json.fetch('upload_id')
          upload_url = upload_json.fetch('uploadURL')
          Logger.debug("Got upload ID: #{upload_id}")

          warning = upload_json['warning']
          Logger.warn(warning) if warning

          [upload_url, upload_id]
        end

        def parse_response(response)
          case response.status
          when 200
            JSON.parse(response.read)
          when 400
            error_message = JSON.parse(response.read)['errorMessage']
            raise "Invalid parameters: #{error_message}"
          when 401, 403
            raise 'Invalid API token'
          else
            raise "Creating upload failed with status #{response.status}"
          end
        end
      end
    end
  end
end
