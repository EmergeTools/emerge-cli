require 'dry/cli'
require 'json'
require 'tty-prompt'

module EmergeCLI
  module Commands
    class Reaper < EmergeCLI::Commands::GlobalOptions
      desc 'Analyze dead code from an Emerge upload'

      option :upload_id, type: :string, required: true, desc: 'Upload ID to analyze'
      option :api_token, type: :string, required: false,
                         desc: 'API token for authentication, defaults to ENV[EMERGE_API_TOKEN]'
      option :project_root, type: :string, required: false,
                         desc: 'Root directory of the project, defaults to current directory'
      option :verbose, type: :boolean, default: false, desc: 'Show detailed class information'

      def initialize(network: nil)
        @network = network
      end

      def call(**options)
        @options = options
        before(options)
        success = false

        begin
          api_token = @options[:api_token] || ENV.fetch('EMERGE_API_TOKEN', nil)
          raise 'API token is required' unless api_token

          @network ||= EmergeCLI::Network.new(api_token:)
          project_root = @options[:project_root] || Dir.pwd

          Sync do
            response = fetch_dead_code(@options[:upload_id])
            result = DeadCodeResult.new(JSON.parse(response.read))

            display_results(result)

            selected_classes = prompt_class_selection(result.filtered_unseen_classes)
            Logger.info "Selected classes:"
            selected_classes.each do |selected_class|
              Logger.info " - #{selected_class['class_name']}"
            end

            confirmed = confirm_deletion(selected_classes.length)
            if !confirmed
              Logger.info "Operation cancelled"
              return false
            end

            Logger.info "Proceeding with deletion..."
            deleter = EmergeCLI::Reaper::CodeDeleter.new(project_root: project_root)
            deleter.delete(selected_classes)
          end
        rescue StandardError => e
          Logger.error "Failed to analyze dead code: #{e.message}"
          raise e
        ensure
          @network&.close
        end

        success
      end

      private

      def fetch_dead_code(upload_id)
        Logger.info 'Fetching dead code analysis...'
        @network.post(
          path: '/deadCode/export',
          query: { uploadId: upload_id },
          headers: { 'Accept' => 'application/json' },
          body: nil
        )
      end

      def prompt_class_selection(unseen_classes)
        return nil if unseen_classes.empty?

        prompt = TTY::Prompt.new

        choices = unseen_classes.map do |item|
          display_name = if item['paths']&.first
            "#{item['class_name']} (#{item['paths'].first})"
          else
            item['class_name']
          end
          {
            name: display_name,
            value: item
          }
        end

        prompt.multi_select(
          "Select classes to delete:".blue,
          choices,
          per_page: 15,
          echo: false,
          filter: true,
          min: 1
        )
      end

      def confirm_deletion(count)
        prompt = TTY::Prompt.new
        prompt.yes?("Are you sure you want to delete #{count} class#{count > 1 ? 'es' : ''}?")
      end

      def display_results(result)
        Logger.info result.to_s

        return unless @options[:verbose]
        Logger.info "\nDetailed Class Information:"
        result.dead_code.each do |item|
          Logger.info "Class: #{item['class_name']}"
          Logger.info "Seen in sessions: #{item['seen']}"
          Logger.info "Paths: #{item['paths']}\n\n"
        end
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
            # .reject { |item| item['seen'] }
            .reject do |item|
              paths = item['paths']
              next false if paths.nil? || paths.empty?

              next true if paths.any? do |path|
                path.include?('SourcePackages/checkouts/') ||
                             path.include?('/Pods/') ||
                             path.include?('/Carthage/') ||
                             path.include?('/Vendor/') ||
                             path.include?('/Sources/')
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
