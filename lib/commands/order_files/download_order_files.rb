require 'dry/cli'

module EmergeCLI
  module Commands
    class DownloadOrderFiles < EmergeCLI::Commands::GlobalOptions
      desc 'Download order files from Emerge'

      option :bundle_id, type: :string, required: true, desc: 'Bundle identifier to download order files for'

      option :api_token, type: :string, required: false,
                         desc: 'API token for authentication, defaults to ENV[EMERGE_API_TOKEN]'

      option :app_version, type: :string, required: true,
                           desc: 'App version to download order files for'

      option :unzip, type: :boolean, required: false,
                     desc: 'Unzip the order file after downloading'

      option :output, type: :string, required: false,
                      desc: 'Output name for the order file, defaults to bundle_id-app_version.gz'

      EMERGE_ORDER_FILE_URL = 'order-files-prod.emergetools.com'.freeze

      def initialize(network: nil)
        @network = network
      end

      def call(**options)
        @options = options
        before(options)

        begin
          api_token = @options[:api_token] || ENV.fetch('EMERGE_API_TOKEN', nil)
          raise 'API token is required' unless api_token

          raise 'Bundle ID is required' unless @options[:bundle_id]
          raise 'App version is required' unless @options[:app_version]

          @network ||= EmergeCLI::Network.new(api_token:, base_url: EMERGE_ORDER_FILE_URL)
          output_name = @options[:output] || "#{@options[:bundle_id]}-#{@options[:app_version]}.gz"

          Sync do
            request = get_order_file(options[:bundle_id], options[:app_version])
            response = request.read

            File.write(output_name, response)

            if @options[:unzip]
              Logger.info 'Unzipping order file...'
              `gunzip -c #{output_name} > #{output_name.gsub('.gz', '')}`
            end

            Logger.info 'Order file downloaded successfully'
          end
        rescue StandardError => e
          Logger.error "Failed to download order file: #{e.message}"
          Logger.error 'Check your parameters and try again'
          raise e
        ensure
          @network&.close
        end
      end

      private

      def get_order_file(bundle_id, app_version)
        @network.get(
          path: "/#{bundle_id}/#{app_version}",
          max_retries: 0
        )
      end
    end
  end
end
