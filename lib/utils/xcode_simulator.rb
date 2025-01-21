require 'English'
require 'zip'
require 'cfpropertylist'
require 'fileutils'

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
      if app_path.end_with?('.ipa')
        Dir.mktmpdir do |tmp_dir|
          Logger.debug "Extracting .app from .ipa in temporary directory: #{tmp_dir}"

          Zip::File.open(app_path) do |zip_file|
            # Find and extract the .app directory from Payload
            app_entry = zip_file.glob('Payload/*.app').first
            raise "No .app found in .ipa file" unless app_entry

            # Get the parent directory name of the .app
            app_dir = File.dirname(app_entry.name)

            # Extract all files from the .app directory
            zip_file.glob("#{app_dir}/**/*").each do |entry|
              entry_path = File.join(tmp_dir, entry.name)
              FileUtils.mkdir_p(File.dirname(entry_path))
              zip_file.extract(entry, entry_path) unless File.exist?(entry_path)
            end

            # Find the extracted .app path
            extracted_app = Dir.glob(File.join(tmp_dir, 'Payload/*.app')).first
            raise "Failed to extract .app from .ipa" unless extracted_app

            # Install the extracted .app
            install_extracted_app(extracted_app)
          end
        end
      else
        install_extracted_app(app_path)
      end
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
  end
end
