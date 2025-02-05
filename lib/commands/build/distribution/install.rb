require 'dry/cli'
require 'cfpropertylist'
require 'zip'
require 'rbconfig'
require 'tmpdir'

module EmergeCLI
  module Commands
    module Build
      module Distribution
        class Install < EmergeCLI::Commands::GlobalOptions
          desc 'Download and install a build from Build Distribution'

          option :api_token, type: :string, required: false,
                             desc: 'API token for authentication, defaults to ENV[EMERGE_API_TOKEN]'
          option :build_id, type: :string, required: true, desc: 'Build ID to download'
          option :install, type: :boolean, default: true, required: false, desc: 'Install the build on the device'
          option :device_id, type: :string, desc: 'Specific device ID to target'
          option :device_type, type: :string, enum: %w[virtual physical any], default: 'any',
                               desc: 'Type of device to target (virtual/physical/any)'
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
              app_id = nil

              begin
                @network ||= EmergeCLI::Network.new(api_token:)

                Logger.info 'Getting build URL...'
                request = get_build_url(@options[:build_id])
                response = parse_response(request)

                platform = response['platform']
                download_url = response['downloadUrl']
                app_id = response['appId']

                extension = platform == 'ios' ? 'ipa' : 'apk'
                output_name = @options[:output] || "#{@options[:build_id]}.#{extension}"

                if File.exist?(output_name)
                  Logger.info "Build file already exists at #{output_name}"
                  print 'Do you want to (i)nstall existing file, (o)verwrite with new download, or (c)ancel? [i/o/c]: '
                  choice = STDIN.gets.chomp.downcase

                  case choice
                  when 'i'
                    Logger.info 'Proceeding with existing file...'
                  when 'o'
                    Logger.info 'Downloading new build...'
                    `curl --progress-bar -L '#{download_url}' -o #{output_name}`
                    Logger.info "✅ Build downloaded to #{output_name}"
                  when 'c'
                    Logger.info 'Operation cancelled'
                    exit(0)
                  else
                    Logger.error 'Invalid choice'
                    exit(1)
                  end
                else
                  Logger.info 'Downloading build...'
                  `curl --progress-bar -L '#{download_url}' -o #{output_name}`
                  Logger.info "✅ Build downloaded to #{output_name}"
                end
              rescue StandardError => e
                Logger.error "❌ Failed to download build: #{e.message}"
                raise e
              ensure
                @network&.close
              end

              begin
                if @options[:install] && !output_name.nil?
                  if platform == 'ios'
                    install_ios_build(output_name, app_id)
                  elsif platform == 'android'
                    install_android_build(output_name)
                  end
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

          def install_ios_build(build_path, app_id)
            device_type = case @options[:device_type]
                          when 'simulator'
                            XcodeDeviceManager::DeviceType::VIRTUAL
                          when 'physical'
                            XcodeDeviceManager::DeviceType::PHYSICAL
                          else
                            XcodeDeviceManager::DeviceType::ANY
                          end

            device_manager = XcodeDeviceManager.new
            device = if @options[:device_id]
                       device_manager.find_device_by_id(@options[:device_id])
                     else
                       device_manager.find_device_by_type(device_type, build_path)
                     end

            Logger.info "Installing build on #{device.device_id}"
            device.install_app(build_path)
            Logger.info '✅ Build installed'

            Logger.info "Launching app #{app_id}..."
            device.launch_app(app_id)
            Logger.info '✅ Build launched'
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
end
