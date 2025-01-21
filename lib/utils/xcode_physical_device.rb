require 'English'
require 'timeout'
require 'zip'
require 'cfpropertylist'
require 'fileutils'

module EmergeCLI
  class XcodePhysicalDevice
    def initialize(device_id)
      @device_id = device_id
    end

    def install_app(ipa_path)
      raise "Non-IPA file provided: #{ipa_path}" unless ipa_path.end_with?('.ipa')

      Logger.info "Installing app to device #{@device_id}..."

      begin
        # Set a timeout since I've noticed xcrun devicectl can occasionally hang for invalid apps
        Timeout.timeout(60) do
          command = "xcrun devicectl device install app --device #{@device_id} \"#{ipa_path}\""
          Logger.debug "Running command: #{command}"

          output = `#{command} 2>&1`
          Logger.debug "Install command output: #{output}"

          if output.include?('ERROR:') || output.include?('error:')
            if output.include?('This provisioning profile cannot be installed on this device')
              bundle_id = extract_bundle_id_from_error(output)
              raise "Failed to install app: The provisioning profile for #{bundle_id} is not valid for this device. Make sure the device's UDID is included in the provisioning profile."
            elsif output.include?('Unable to Install')
              error_message = output.match(/Unable to Install.*\n.*NSLocalizedRecoverySuggestion = ([^\n]+)/)&.[](1)
              check_device_compatibility(ipa_path)
              raise "Failed to install app: #{error_message || 'Unknown error'}"
            else
              check_device_compatibility(ipa_path)
              raise "Failed to install app: #{output}"
            end
          end

          success = $CHILD_STATUS.success?
          unless success
            check_device_compatibility(ipa_path)
            raise "Installation failed with exit code #{$CHILD_STATUS.exitstatus}"
          end
        end
      rescue Timeout::Error
        raise 'Installation timed out after 30 seconds. The device might be locked or installation might be stuck. Try unlocking the device and trying again.'
      end

      true
    end

    def launch_app(bundle_id)
      Logger.info "Launching app #{bundle_id} on device #{@device_id}..."
      command = "xcrun devicectl device process launch --device #{@device_id} #{bundle_id}"
      Logger.debug "Running command: #{command}"

      begin
        Timeout.timeout(30) do
          output = `#{command} 2>&1`
          success = $CHILD_STATUS.success?

          unless success
            Logger.debug "Launch command output: #{output}"
            if output.include?('The operation couldn\'t be completed. Application is restricted')
              raise 'Failed to launch app: The app is restricted. Make sure the device is unlocked and the app is allowed to run.'
            elsif output.include?('The operation couldn\'t be completed. Unable to launch')
              raise 'Failed to launch app: Unable to launch. The app might be in a bad state - try uninstalling and reinstalling.'
            else
              raise "Failed to launch app #{bundle_id} on device: #{output}"
            end
          end
        end
      rescue Timeout::Error
        raise 'Launch timed out after 30 seconds. The device might be locked. Try unlocking the device and trying again.'
      end

      true
    end

    private

    def check_device_compatibility(ipa_path)
      supported_platforms = XcodeDeviceManager.get_supported_platforms(ipa_path)
      Logger.debug "Supported platforms: #{supported_platforms.join(', ')}"

      unless supported_platforms.include?('iPhoneOS')
        raise 'This build is not compatible with physical devices. Please use a simulator or make your build compatible with physical devices.'
      end

      Logger.debug 'Build is compatible with physical devices'
    end

    def extract_bundle_id_from_error(output)
      # Extract bundle ID from error message like "...profile for com.emerge.hn.Hacker-News :"
      output.match(/profile for ([\w\.-]+) :/)&.[](1) || 'unknown bundle ID'
    end
  end
end
