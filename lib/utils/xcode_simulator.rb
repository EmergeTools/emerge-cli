require 'English'
require 'zip'
require 'cfpropertylist'

module EmergeCLI
  class XcodeSimulator
    def initialize(device_id)
      @device_id = device_id
    end

    def boot
      Logger.info "Booting simulator #{@device_id}..."
      result = system("xcrun simctl boot #{@device_id}")
      raise 'Failed to boot simulator' unless result
    end

    def install_app(app_path)
      command = "xcrun simctl install #{@device_id} \"#{app_path}\""
      Logger.debug "Running command: #{command}"

      output = `#{command} 2>&1`
      success = $CHILD_STATUS.success?

      return if success
      Logger.debug "Install command output: #{output}"
      check_simulator_compatibility(app_path)
      raise "Failed to install build on simulator #{@device_id}"
    end

    private

    def check_simulator_compatibility(ipa_path)
      Dir.mktmpdir do |_tmp_dir|
        Zip::File.open(ipa_path) do |zip_file|
          zip_file.each do |entry|
            Logger.debug "Entry: #{entry.name}"
            next unless entry.name.start_with?('Payload/') && entry.name.end_with?('.app/')
            app_dir = entry.name
            info_plist_path = "#{app_dir}Info.plist"

            next unless (info_plist_entry = zip_file.find_entry(info_plist_path))
            # Extract and read Info.plist
            info_plist_content = info_plist_entry.get_input_stream.read
            plist = CFPropertyList::List.new(data: info_plist_content)
            info_plist = CFPropertyList.native_types(plist.value)

            supported_platforms = info_plist['CFBundleSupportedPlatforms'] || []
            Logger.debug "Supported platforms: #{supported_platforms.join(', ')}"

            unless supported_platforms.include?('iPhoneSimulator')
              raise 'This build is not compatible with simulators. Please use a real device or make your build compatible with simulators.'
            end

            Logger.debug 'Build is compatible with simulators'
          end
        end
      end
    end
  end
end
