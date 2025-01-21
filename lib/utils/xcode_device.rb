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
      unless system(command)
        # If install fails on simulator, check compatibility
        if !@device_id.start_with?("00")
          macho_parser = EmergeCLI::MachOParser.new
          unless macho_parser.is_simulator_compatible?(app_path)
            raise "❌ This build is not compatible with simulators. Please use a real device or get a simulator build."
          end
        end
        raise "❌ Failed to install build"
      end
    end

    private

    def find_and_boot_simulator
      simulators = `xcrun simctl list devices`
      # Find all iPhone simulators with their versions
      # If multiple simulators are found, take the latest OS version
      iphone_simulators = simulators.scan(/iPhone \d+(?:\s\(\d+\.\d+\))?.*?\(([\w-]+)\).*?(\(.*?\))/)
        .map do |match|
          id = match[0]
          state = match[1].tr('()', '')
          version = simulators.match(/iPhone \d+(?:\s\((\d+\.\d+)\))?.*?#{id}/)&.[](1)&.to_f || 0
          [id, state, version]
        end
        .sort_by { |_, _, version| version }
        .reverse

      raise "No available iPhone simulator found" unless iphone_simulators.any?

      simulator_id, simulator_state, version = iphone_simulators.first
      version_str = version.zero? ? "" : " (#{version})"
      Logger.info "Found simulator #{simulator_id}#{version_str} (#{simulator_state})"

      unless simulator_state == "Booted"
        Logger.info "Booting simulator #{simulator_id}..."
        result = system("xcrun simctl boot #{simulator_id}")
        raise "Failed to boot simulator" unless result
      end

      simulator_id
    end
  end
end
