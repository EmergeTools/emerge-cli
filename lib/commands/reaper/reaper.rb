require 'dry/cli'
require 'json'

module EmergeCLI
  module Commands
    class Reaper < EmergeCLI::Commands::GlobalOptions
      desc 'Analyze dead code from an Emerge upload'

      option :upload_id, type: :string, required: true, desc: 'Upload ID to analyze'
      option :api_token, type: :string, required: false,
                        desc: 'API token for authentication, defaults to ENV[EMERGE_API_TOKEN]'
      option :verbose, type: :boolean, default: false, desc: 'Show detailed class information'

      def initialize(network: nil)
        @network = network
      end

      def call(**options)
        @options = options
        success = false

        begin
          api_token = @options[:api_token] || ENV.fetch('EMERGE_API_TOKEN', nil)
          raise 'API token is required' unless api_token

          @network ||= EmergeCLI::Network.new(api_token:)

          Sync do
            response = fetch_dead_code(@options[:upload_id])
            result = DeadCodeResult.new(JSON.parse(response.read))

            display_results(result)
            success = true
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

      class DeadCodeResult
        attr_reader :metadata, :dead_code, :counts, :pagination

        def initialize(data)
          @metadata = data['metadata']
          @dead_code = data['dead_code']
          @counts = data['counts']
          @pagination = data['pagination']
        end

        def to_s
          <<~SUMMARY
            Dead Code Analysis Results:
            Organization: #{@metadata['org_id']}
            Platform: #{@metadata['platform']}
            App Version: #{@metadata['version']}

            Statistics:
            - Total User Sessions: #{@counts['user_sessions']}
            - Seen Classes: #{@counts['seen_classes']}
            - Unseen Classes: #{@counts['unseen_classes']}

            Page #{@pagination['currentPage']} of #{@pagination['totalPages']}
          SUMMARY
        end
      end

      def fetch_dead_code(upload_id)
        Logger.info 'Fetching dead code analysis...'
        @network.post(
          path: '/deadCode/export',
          query: { uploadId: upload_id },
          headers: { 'Accept' => 'application/json' },
          body: nil
        )
      end

      def display_results(result)
        Logger.info result.to_s

        if @options[:verbose]
          Logger.info "\nDetailed Class Information:"
          result.dead_code.each do |item|
            Logger.info "Class: #{item['class_name']}"
            Logger.info "Seen in sessions: #{item['seen']}"
            Logger.info "Paths: #{item['paths']}\n\n"
          end
        end
      end
    end
  end
end
