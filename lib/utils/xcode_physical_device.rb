require 'English'
module EmergeCLI
  class XcodePhysicalDevice
    def initialize(device_id)
      @device_id = device_id
    end

    def install_app(app_path)
      command = "xcrun devicectl device install app -d #{@device_id} #{app_path}"
      Logger.debug "Running command: #{command}"

      output = `#{command} 2>&1`
      success = $CHILD_STATUS.success?

      return if success
      Logger.debug "Install command output: #{output}"
      raise "Failed to install build on device #{@device_id}"
    end
  end
end
