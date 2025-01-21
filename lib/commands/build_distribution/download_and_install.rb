require 'dry/cli'
require 'cfpropertylist'
require 'zip'
require 'rbconfig'
require 'tmpdir'

module EmergeCLI
  module Commands
    module BuildDistribution
      class DownloadAndInstall < EmergeCLI::Commands::GlobalOptions
        desc 'Download build from Build Distribution'

        option :api_token, type: :string, required: false,
                           desc: 'API token for authentication, defaults to ENV[EMERGE_API_TOKEN]'
        option :build_id, type: :string, required: true, desc: 'Build ID to download'
        option :install, type: :boolean, default: true, required: false, desc: 'Install the build on the device'
        option :device_id, type: :string, required: false, desc: 'Device id to install the build'
        option :output, type: :string, required: false, desc: 'Output path for the downloaded build'

        def initialize(network: nil)
          @network = network
        end

        def call(**options)
          @options = options
          before(options)

          Sync do
            api_token = @options[:api_token] || ENV.fetch('EMERGE_API_TOKEN', nil)
            raise 'API token is required' unless api_token

            raise 'Build ID is required' unless @options[:build_id]

            output_name = nil

            begin
              @network ||= EmergeCLI::Network.new(api_token:)

              Logger.info 'Getting build URL...'
              request = get_build_url(@options[:build_id])
              response = parse_response(request)

              platform = response['platform']
              download_url = response['downloadUrl']

              extension = platform == 'ios' ? 'ipa' : 'apk'
              Logger.info 'Downloading build...'
              output_name = @options[:output] || "#{@options[:build_id]}.#{extension}"
              `curl --progress-bar -L '#{download_url}' -o #{output_name} `
              Logger.info "✅ Build downloaded to #{output_name}"
            rescue StandardError => e
              Logger.error "❌ Failed to download build: #{e.message}"
              raise e
            ensure
              @network&.close
            end

            begin
              if @options[:install] && !output_name.nil?
                install_ios_build(output_name) if platform == 'ios'
                install_android_build(output_name) if platform == 'android'
              end
            rescue StandardError => e
              Logger.error "❌ Failed to install build: #{e.message}"
              raise e
            end
          end
        end

        private

        def get_build_url(build_id)
          @network.get(
            path: '/distribution/downloadUrl',
            max_retries: 3,
            query: {
              buildId: build_id
            }
          )
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
            raise "Getting build failed with status #{response.status}"
          end
        end

        def install_ios_build(build_path)
          device = EmergeCLI::XcodeDeviceManager.new(device_id: @options[:device_id])
          device.install_app(build_path)
          Logger.info '✅ Build installed'
        end

        def install_android_build(build_path)
          command = "adb -s #{@options[:device_id]} install #{build_path}"
          Logger.debug "Running command: #{command}"
          `#{command}`

          Logger.info '✅ Build installed'
        end
      end
    end
  end
end
