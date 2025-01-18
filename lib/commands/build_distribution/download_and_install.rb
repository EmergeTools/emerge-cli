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

              if @options[:install]
                install_ios_build(output_name) if platform == 'ios'
                install_android_build(output_name) if platform == 'android'
              end
            rescue StandardError => e
              Logger.error "Failed to download build: #{e.message}"
              Logger.error 'Check your parameters and try again'
              raise e
            ensure
              @network&.close
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
          if @options[:device_id]
            command = "xcrun devicectl device install app -d #{@options[:device_id]} #{build_path}"
          else
            # Get list of available simulators
            simulators = `xcrun simctl list devices available`
            # Find first available iPhone simulator (preferably iPhone 15)
            simulator_id = if simulators =~ /iPhone 15.*?\(([\w-]+)\)/
                            $1
                          elsif simulators =~ /iPhone.*?\(([\w-]+)\)/
                            $1
                          else
                            raise "No available iPhone simulator found"
                          end

            Logger.info "Booting simulator #{simulator_id}..."
            result = system("xcrun simctl boot #{simulator_id}")
            raise "Failed to boot simulator" unless result

            Logger.info "Installing build on simulator..."
            command = "xcrun simctl install #{simulator_id} #{build_path}"

            # If the install fails, check if the build is simulator compatible for a better error message
            unless system(command)
              Dir.mktmpdir do |tmp_dir|
                Zip::File.open(build_path) do |zip_file|
                  app_entry = zip_file.glob('Payload/*.app').first
                  raise "❌ No .app found in IPA" unless app_entry

                  app_name = File.basename(app_entry.name, '.app')
                  binary_path = "Payload/#{File.basename(app_entry.name)}/#{app_name}"
                  zip_file.extract(binary_path, "#{tmp_dir}/binary")

                  macho_parser = EmergeCLI::MachOParser.new
                  unless macho_parser.is_simulator_compatible?("#{tmp_dir}/binary")
                    raise "❌ This build is not compatible with simulators. Please use a real device or get a simulator build."
                  end
                end
              end
              # If we get here, it's simulator compatible but failed for another reason
              raise "❌ Failed to install build"
            end
          end

          Logger.debug "Running command: #{command}"
          result = system(command)
          raise "❌ Failed to install build" unless result

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
