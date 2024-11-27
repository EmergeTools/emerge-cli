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

        def class_prefix_stats(min_prefix_length: 2, min_group_size: 2)
          # Group unseen classes by their prefixes
          prefix_groups = {}

          # Only process unseen classes
          unseen_code = dead_code.reject { |item| item['seen'] }

          unseen_code.each do |item|
            class_name = item['class_name']
            parts = class_name.split('.')

            # Try different prefix lengths
            (1..parts.length).each do |length|
              prefix = parts.take(length).join('.')
              next if prefix.length < min_prefix_length
              prefix_groups[prefix] ||= []
              prefix_groups[prefix] << item
            end
          end

          # Filter and sort groups
          significant_groups = prefix_groups
            .select { |_, group| group.length >= min_group_size }
            .sort_by { |_, group| -group.length }
            .first(10)  # Top 10 most common prefixes

          return "No significant unseen class groupings found." if significant_groups.empty?

          output = ["Unseen Class Prefix Analysis (showing top 10 groups):"]

          significant_groups.each do |prefix, group|
            output << "\n#{prefix}.* (#{group.length} unseen classes)"
            output << "  Example classes:"
            group.first(3).each do |item|
              output << "  - #{item['class_name']}"
            end
          end

          output.join("\n")
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

            #{class_prefix_stats}

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
