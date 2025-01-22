require 'json'
require_relative 'xcode_simulator'
require 'zip'
require 'cfpropertylist'

module EmergeCLI
  class XcodeDeviceManager
    class DeviceType
      VIRTUAL = :virtual
      PHYSICAL = :physical
      ANY = :any
    end

    def initialize(environment: Environment.new)
      @environment = environment
    end

    class << self
      def get_supported_platforms(ipa_path)
        return [] unless ipa_path&.end_with?('.ipa')

        Zip::File.open(ipa_path) do |zip_file|
          app_entry = zip_file.glob('**/*.app/').first ||
                      zip_file.glob('**/*.app').first ||
                      zip_file.find { |entry| entry.name.end_with?('.app/') || entry.name.end_with?('.app') }

          raise 'No .app found in .ipa file' unless app_entry

          app_dir = app_entry.name.end_with?('/') ? app_entry.name.chomp('/') : app_entry.name
          info_plist_path = "#{app_dir}/Info.plist"
          info_plist_entry = zip_file.find_entry(info_plist_path)
          raise 'Info.plist not found in app bundle' unless info_plist_entry

          info_plist_content = info_plist_entry.get_input_stream.read
          plist = CFPropertyList::List.new(data: info_plist_content)
          info_plist = CFPropertyList.native_types(plist.value)

          info_plist['CFBundleSupportedPlatforms'] || []
        end
      end
    end

    def find_device_by_id(device_id)
      Logger.debug "Looking for device with ID: #{device_id}"
      devices_json = execute_command('xcrun xcdevice list')
      devices_data = JSON.parse(devices_json)

      found_device = devices_data.find { |device| device['identifier'] == device_id }
      raise "No device found with ID: #{device_id}" unless found_device

      device_type = found_device['simulator'] ? 'simulator' : 'physical'
      Logger.info "✅ Found device: #{found_device['name']} " \
                  "(#{found_device['identifier']}, #{device_type})"
      if found_device['simulator']
        XcodeSimulator.new(found_device['identifier'])
      else
        XcodePhysicalDevice.new(found_device['identifier'])
      end
    end

    def find_device_by_type(device_type, ipa_path)
      case device_type
      when DeviceType::VIRTUAL
        find_and_boot_most_recently_used_simulator
      when DeviceType::PHYSICAL
        find_connected_device
      when DeviceType::ANY
        # Check supported platforms in Info.plist to make intelligent choice
        supported_platforms = self.class.get_supported_platforms(ipa_path)
        Logger.debug "Build supports platforms: #{supported_platforms.join(', ')}"

        if supported_platforms.include?('iPhoneOS')
          device = find_connected_device
          return device if device

          # Only fall back to simulator if it's also supported
          unless supported_platforms.include?('iPhoneSimulator')
            raise 'Build only supports physical devices, but no device is connected'
          end
          Logger.info 'No physical device found, falling back to simulator since build supports both'
          find_and_boot_most_recently_used_simulator

        elsif supported_platforms.include?('iPhoneSimulator')
          find_and_boot_most_recently_used_simulator
        else
          raise "Build doesn't support either physical devices or simulators"
        end
      end
    end

    private

    def execute_command(command)
      @environment.execute_command(command)
    end

    def find_connected_device
      Logger.info 'Finding connected device...'
      devices_json = execute_command('xcrun xcdevice list')
      Logger.debug "Device list output: #{devices_json}"

      devices_data = JSON.parse(devices_json)
      physical_devices = devices_data
                         .select do |device|
        device['simulator'] == false &&
          device['ignored'] == false &&
          device['available'] == true &&
          device['platform'] == 'com.apple.platform.iphoneos'
      end

      Logger.debug "Found physical devices: #{physical_devices}"

      if physical_devices.empty?
        Logger.info 'No physical connected device found'
        return nil
      end

      device = physical_devices.first
      Logger.info "Found connected physical device: #{device['name']} (#{device['identifier']})"
      XcodePhysicalDevice.new(device['identifier'])
    end

    def find_and_boot_most_recently_used_simulator
      Logger.info 'Finding and booting most recently used simulator...'
      simulators_json = execute_command('xcrun simctl list devices --json')
      Logger.debug "Simulators JSON: #{simulators_json}"

      simulators_data = JSON.parse(simulators_json)

      simulators = simulators_data['devices'].flat_map do |runtime, devices|
        next [] unless runtime.include?('iOS') # Only include iOS devices

        devices.select do |device|
          (device['name'].start_with?('iPhone', 'iPad') &&
            device['isAvailable'] &&
            !device['isDeleted'])
        end.map do |device|
          version = runtime.match(/iOS-(\d+)-(\d+)/)&.captures&.join('.').to_f
          last_booted = device['lastBootedAt'] ? Time.parse(device['lastBootedAt']) : Time.at(0)
          [device['udid'], device['state'], version, last_booted]
        end
      end.sort_by { |_, _, _, last_booted| last_booted }.reverse

      Logger.debug "Simulators: #{simulators}"

      raise 'No available simulator found' unless simulators.any?

      simulator_id, simulator_state, version, last_booted = simulators.first
      version_str = version.zero? ? '' : " (#{version})"
      last_booted_str = last_booted == Time.at(0) ? 'never' : last_booted.strftime('%Y-%m-%d %H:%M:%S')
      Logger.info "Found simulator #{simulator_id}#{version_str} (#{simulator_state}, last booted: #{last_booted_str})"

      simulator = XcodeSimulator.new(simulator_id, environment: @environment)
      simulator.boot unless simulator_state == 'Booted'
      simulator
    end
  end
end
