require 'zip'
require 'cfpropertylist'
require 'json'

module EmergeCLI
  class XcodeDevice
    def initialize(device_id: nil)
      @device_id = device_id || find_and_boot_simulator
    end

    def install_app(app_path)
      # Device IDs for physical devices start with 00
      command = if @device_id.start_with?("00")
        "xcrun devicectl device install app -d #{@device_id} #{app_path}"
      else
        "xcrun simctl install #{@device_id} \"#{app_path}\""
      end

      Logger.debug "Running command: #{command}"
      # Capture stderr and redirect to debug log
      output = `#{command} 2>&1`
      success = $?.success?

      unless success
        Logger.debug "Install command output: #{output}"
        # If install fails on simulator, check compatibility
        if !@device_id.start_with?("00")
          check_simulator_compatibility(app_path)
        end
        raise "Failed to install build on device #{@device_id}"
      end
    end

    private

    def find_and_boot_simulator
      simulators_json = `xcrun simctl list devices --json`
      Logger.debug "Simulators JSON: #{simulators_json}"

      simulators_data = JSON.parse(simulators_json)

      # Collect all available iPhone simulators across all runtimes
      iphone_simulators = simulators_data['devices'].flat_map do |runtime, devices|
        next [] unless runtime.include?('iOS') # Only include iOS devices

        devices.select { |device|
          device['name'].start_with?('iPhone') &&
          device['isAvailable'] &&
          !device['isDeleted']
        }.map do |device|
          version = runtime.match(/iOS-(\d+)-(\d+)/)&.captures&.join('.').to_f
          last_booted = device['lastBootedAt'] ? Time.parse(device['lastBootedAt']) : Time.at(0)
          [device['udid'], device['state'], version, last_booted]
        end
      end.sort_by { |_, _, _, last_booted| last_booted }.reverse # Sort by most recently booted

      Logger.debug "iPhone simulators: #{iphone_simulators}"

      raise "No available iPhone simulator found" unless iphone_simulators.any?

      simulator_id, simulator_state, version, last_booted = iphone_simulators.first
      version_str = version.zero? ? "" : " (#{version})"
      last_booted_str = last_booted == Time.at(0) ? "never" : last_booted.strftime("%Y-%m-%d %H:%M:%S")
      Logger.info "Found simulator #{simulator_id}#{version_str} (#{simulator_state}, last booted: #{last_booted_str})"

      unless simulator_state == "Booted"
        Logger.info "Booting simulator #{simulator_id}..."
        result = system("xcrun simctl boot #{simulator_id}")
        raise "Failed to boot simulator" unless result
      end

      simulator_id
    end

    def check_simulator_compatibility(ipa_path)
      Dir.mktmpdir do |tmp_dir|
        Zip::File.open(ipa_path) do |zip_file|
          zip_file.each do |entry|
            Logger.debug "Entry: #{entry.name}"
            if entry.name.start_with?('Payload/') && entry.name.end_with?('.app/')
              app_dir = entry.name
              info_plist_path = "#{app_dir}Info.plist"

              if info_plist_entry = zip_file.find_entry(info_plist_path)
                # Extract and read Info.plist
                info_plist_content = info_plist_entry.get_input_stream.read
                plist = CFPropertyList::List.new(data: info_plist_content)
                info_plist = CFPropertyList.native_types(plist.value)

                supported_platforms = info_plist['CFBundleSupportedPlatforms'] || []
                Logger.debug "Supported platforms: #{supported_platforms.join(', ')}"

                unless supported_platforms.include?('iPhoneSimulator')
                  raise "This build is not compatible with simulators. Please use a real device or make your build compatible with simulators."
                end

                Logger.debug "Build is compatible with simulators"
              end
            end
          end
        end
      end
    end
  end
end
