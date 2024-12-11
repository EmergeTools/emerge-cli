require 'dry/cli'
require 'json'
require 'tty-prompt'

module EmergeCLI
  module Commands
    class Reaper < EmergeCLI::Commands::GlobalOptions
      desc 'Analyze dead code from an Emerge upload'

      option :upload_id, type: :string, required: true, desc: 'Upload ID to analyze'
      option :project_root, type: :string, required: true,
                            desc: 'Root directory of the project, defaults to current directory'

      option :api_token, type: :string, required: false,
                         desc: 'API token for authentication, defaults to ENV[EMERGE_API_TOKEN]'

      option :profile, type: :boolean, default: false, desc: 'Enable performance profiling metrics'

      option :skip_delete_usages, type: :boolean, default: false,
                                  desc: 'Skip deleting usages of the type (experimental feature)'

      def initialize(network: nil)
        @network = network
      end

      def call(**options)
        @options = options
        @profiler = EmergeCLI::Profiler.new(enabled: options[:profile])
        @prompt = TTY::Prompt.new
        before(options)
        success = false

        begin
          api_token = @options[:api_token] || ENV.fetch('EMERGE_API_TOKEN', nil)
          raise 'API token is required' unless api_token

          @network ||= EmergeCLI::Network.new(api_token:)
          project_root = @options[:project_root] || Dir.pwd

          Sync do
            all_data = @profiler.measure('fetch_dead_code') { fetch_all_dead_code(@options[:upload_id]) }
            result = @profiler.measure('parse_dead_code') { DeadCodeResult.new(all_data) }

            Logger.info result.to_s

            selected_types = prompt_class_selection(result.filtered_unseen_classes, result.metadata['platform'])
            Logger.info 'Selected classes:'
            selected_types.each do |selected_class|
              Logger.info " - #{selected_class['class_name']}"
            end

            confirmed = confirm_deletion(selected_types.length)
            if !confirmed
              Logger.info 'Operation cancelled'
              return false
            end

            Logger.info 'Proceeding with deletion...'
            platform = result.metadata['platform']
            deleter = EmergeCLI::Reaper::CodeDeleter.new(
              project_root: project_root,
              platform: platform,
              profiler: @profiler,
              skip_delete_usages: options[:skip_delete_usages]
            )
            @profiler.measure('delete_types') { deleter.delete_types(selected_types) }
          end

          @profiler.report if @options[:profile]
          success = true
        rescue StandardError => e
          Logger.error "Failed to analyze dead code: #{e.message}"
          raise e
        ensure
          @network&.close
        end

        success
      end

      private

      def fetch_all_dead_code(upload_id)
        Logger.info 'Fetching dead code analysis (this may take a while for large codebases)...'

        page = 1
        combined_data = nil

        loop do
          response = fetch_dead_code_page(upload_id, page)
          data = JSON.parse(response.read)

          if combined_data.nil?
            combined_data = data  # First page, use as base
          else
            # Merge dead_code arrays
            combined_data['dead_code'].concat(data.fetch('dead_code', []))

            # Update counts safely
            counts = combined_data['counts']
            new_counts = data.dig('counts') || {}

            counts['seen_classes'] += new_counts.fetch('seen_classes', 0)
            counts['unseen_classes'] += new_counts.fetch('unseen_classes', 0)
          end

          # Check if we've reached the last page
          current_page = data.dig('pagination', 'current_page')
          total_pages = data.dig('pagination', 'total_pages')

          break unless current_page && total_pages && current_page < total_pages

          page += 1
          Logger.info "Fetching page #{page} of #{total_pages}..."
        end

        combined_data
      end

      def fetch_dead_code_page(upload_id, page)
        @network.post(
          path: '/deadCode/export',
          query: {
            uploadId: upload_id,
            page: page
          },
          headers: { 'Accept' => 'application/json' },
          body: nil
        )
      end

      def prompt_class_selection(unseen_classes, platform)
        return nil if unseen_classes.empty?

        choices = unseen_classes.map do |item|
          display_name = if item['paths']&.first && platform == 'ios'
                           "#{item['class_name']} (#{item['paths'].first})"
                         else
                           item['class_name']
                         end
          {
            name: display_name,
            value: item
          }
        end

        @prompt.multi_select(
          'Select classes to delete:'.blue,
          choices,
          per_page: 15,
          echo: false,
          filter: true,
          min: 1
        )
      end

      def confirm_deletion(count)
        @prompt.yes?("Are you sure you want to delete #{count} type#{count > 1 ? 's' : ''}?")
      end

      class DeadCodeResult
        attr_reader :metadata, :dead_code, :counts, :pagination

        def initialize(data)
          @metadata = data['metadata']
          @dead_code = data['dead_code']
          @counts = data['counts']
          @pagination = data['pagination']
        end

        def filtered_unseen_classes
          @filtered_unseen_classes ||= dead_code
                                       .reject { |item| item['seen'] }
                                       .reject do |item|
            paths = item['paths']
            next false if paths.nil? || paths.empty?

            next true if paths.any? do |path|
              path.include?('/SourcePackages/checkouts/') ||
              path.include?('/Pods/') ||
              path.include?('/Carthage/') ||
              path.include?('/Vendor/') ||
              path.include?('/Sources/') ||
              path.include?('/DerivedSources/')
            end

            next false if paths.none? do |path|
              path.end_with?('.swift', '.java', '.kt')
            end
          end
        end

        def to_s
          <<~SUMMARY.yellow

            Dead Code Analysis Results:
            App ID: #{@metadata['app_id']}
            App Version: #{@metadata['version']}
            Platform: #{@metadata['platform']}

            Statistics:
            - Total User Sessions: #{@counts['user_sessions']}
            - Seen Classes: #{@counts['seen_classes']}
            - Unseen Classes: #{@counts['unseen_classes']}
          SUMMARY
        end
      end
    end
  end
end
