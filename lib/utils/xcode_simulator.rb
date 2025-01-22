require 'English'
require 'zip'
require 'cfpropertylist'
require 'fileutils'

module EmergeCLI
  class XcodeSimulator
    attr_reader :device_id

    def initialize(device_id, environment: Environment.new)
      @device_id = device_id
      @environment = environment
    end

    def boot
      Logger.info "Booting simulator #{@device_id}..."
      output = @environment.execute_command("xcrun simctl boot #{@device_id}")
      raise 'Failed to boot simulator' if output.include?('error') || output.include?('failed')
    end

    def install_app(ipa_path)
      raise "Non-IPA file provided: #{ipa_path}" unless ipa_path.end_with?('.ipa')

      Dir.mktmpdir do |tmp_dir|
        Logger.debug "Extracting .app from .ipa in temporary directory: #{tmp_dir}"

        Zip::File.open(ipa_path) do |zip_file|
          # Debug: List all entries to see what's in the IPA
          Logger.debug 'IPA contents:'
          zip_file.each do |entry|
            Logger.debug "  #{entry.name}"
          end

          # Try different patterns to find the .app directory
          app_entry = zip_file.glob('**/*.app/').first ||
                      zip_file.glob('**/*.app').first ||
                      zip_file.find { |entry| entry.name.end_with?('.app/') || entry.name.end_with?('.app') }

          raise 'No .app found in .ipa file' unless app_entry
          Logger.debug "Found app entry: #{app_entry.name}"

          # Extract the .app directory and its contents
          app_dir = app_entry.name.end_with?('/') ? app_entry.name.chomp('/') : app_entry.name
          pattern = "#{File.dirname(app_dir)}/#{File.basename(app_dir)}/**/*"
          Logger.debug "Using glob pattern: #{pattern}"

          zip_file.glob(pattern).each do |entry|
            entry_path = File.join(tmp_dir, entry.name)
            FileUtils.mkdir_p(File.dirname(entry_path))
            zip_file.extract(entry, entry_path) unless File.exist?(entry_path)
          end

          extracted_app = Dir.glob(File.join(tmp_dir, '**/*.app')).first
          raise 'Failed to extract .app from .ipa' unless extracted_app
          Logger.debug "Extracted app at: #{extracted_app}"

          install_extracted_app(extracted_app)
        end
      end
    end

    def launch_app(bundle_id)
      Logger.info "Launching app #{bundle_id} on simulator #{@device_id}..."
      command = "xcrun simctl launch #{@device_id} #{bundle_id}"
      Logger.debug "Running command: #{command}"

      output = `#{command} 2>&1`
      success = $CHILD_STATUS.success?

      unless success
        Logger.debug "Launch command output: #{output}"
        raise "Failed to launch app #{bundle_id} on simulator"
      end

      true
    end

    private

    def install_extracted_app(app_path)
      command = "xcrun simctl install #{@device_id} \"#{app_path}\""
      Logger.debug "Running command: #{command}"

      output = `#{command} 2>&1`
      success = $CHILD_STATUS.success?

      return if success
      Logger.debug "Install command output: #{output}"
      check_simulator_compatibility(app_path)
      raise "Failed to install build on simulator #{@device_id}"
    end

    def check_simulator_compatibility(app_path)
      supported_platforms = if app_path.end_with?('.ipa')
                              XcodeDeviceManager.get_supported_platforms(app_path)
                            else
                              info_plist_path = File.join(app_path, 'Info.plist')
                              raise 'Info.plist not found in app bundle' unless File.exist?(info_plist_path)

                              plist = CFPropertyList::List.new(file: info_plist_path)
                              info_plist = CFPropertyList.native_types(plist.value)
                              info_plist['CFBundleSupportedPlatforms'] || []
                            end

      Logger.debug "Supported platforms: #{supported_platforms.join(', ')}"

      unless supported_platforms.include?('iPhoneSimulator')
        raise 'This build is not compatible with simulators. Please use a real device or make your build compatible with simulators.'
      end

      Logger.debug 'Build is compatible with simulators'
    end
  end
end
