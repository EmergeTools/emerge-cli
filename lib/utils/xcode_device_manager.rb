require 'json'
require_relative 'xcode_simulator'

module EmergeCLI
  class XcodeDeviceManager
    def initialize(device_id: nil)
      @device_id = device_id
    end

    def get_device
      if @device_id
        create_device(@device_id)
      else
        find_and_boot_simulator
      end
    end

    private

    def create_device(device_id)
      if device_id.start_with?('00')
        XcodePhysicalDevice.new(device_id)
      else
        XcodeSimulator.new(device_id)
      end
    end

    def find_and_boot_simulator
      simulators_json = `xcrun simctl list devices --json`
      Logger.debug "Simulators JSON: #{simulators_json}"

      simulators_data = JSON.parse(simulators_json)

      # Collect all available iPhone simulators across all runtimes
      iphone_simulators = simulators_data['devices'].flat_map do |runtime, devices|
        next [] unless runtime.include?('iOS') # Only include iOS devices

        devices.select do |device|
          device['name'].start_with?('iPhone') &&
            device['isAvailable'] &&
            !device['isDeleted']
        end.map do |device|
          version = runtime.match(/iOS-(\d+)-(\d+)/)&.captures&.join('.').to_f
          last_booted = device['lastBootedAt'] ? Time.parse(device['lastBootedAt']) : Time.at(0)
          [device['udid'], device['state'], version, last_booted]
        end
      end.sort_by { |_, _, _, last_booted| last_booted }.reverse # Sort by most recently booted

      Logger.debug "iPhone simulators: #{iphone_simulators}"

      raise 'No available iPhone simulator found' unless iphone_simulators.any?

      simulator_id, simulator_state, version, last_booted = iphone_simulators.first
      version_str = version.zero? ? '' : " (#{version})"
      last_booted_str = last_booted == Time.at(0) ? 'never' : last_booted.strftime('%Y-%m-%d %H:%M:%S')
      Logger.info "Found simulator #{simulator_id}#{version_str} (#{simulator_state}, last booted: #{last_booted_str})"

      simulator = XcodeSimulator.new(simulator_id)
      simulator.boot unless simulator_state == 'Booted'
      simulator
    end
  end
end
