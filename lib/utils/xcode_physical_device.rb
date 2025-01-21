require 'English'
require 'timeout'

module EmergeCLI
  class XcodePhysicalDevice
    def initialize(device_id)
      @device_id = device_id
    end

    def install_app(app_path)
      Logger.info "Installing app to device #{@device_id}..."

      begin
        Timeout.timeout(60) do
          command = "xcrun devicectl device install app --device #{@device_id} \"#{app_path}\""
          Logger.debug "Running command: #{command}"

          output = `#{command} 2>&1`
          Logger.debug "Install command output: #{output}"

          if output.include?('ERROR:') || output.include?('error:')
            if output.include?('This provisioning profile cannot be installed on this device')
              bundle_id = extract_bundle_id_from_error(output)
              raise "Failed to install app: The provisioning profile for #{bundle_id} is not valid for this device. Make sure the device's UDID is included in the provisioning profile."
            elsif output.include?('Unable to Install')
              error_message = output.match(/Unable to Install.*\n.*NSLocalizedRecoverySuggestion = ([^\n]+)/)&.[](1)
              raise "Failed to install app: #{error_message || 'Unknown error'}"
            else
              raise "Failed to install app: #{output}"
            end
          end

          success = $CHILD_STATUS.success?
          raise "Installation failed with exit code #{$CHILD_STATUS.exitstatus}" unless success
        end
      rescue Timeout::Error
        raise "Installation timed out after 30 seconds. The device might be locked or installation might be stuck. Try unlocking the device and trying again."
      end

      true
    end

    private

    def extract_bundle_id_from_error(output)
      # Extract bundle ID from error message like "...profile for com.emerge.hn.Hacker-News :"
      output.match(/profile for ([\w\.-]+) :/)&.[](1) || 'unknown bundle ID'
    end
  end
end
