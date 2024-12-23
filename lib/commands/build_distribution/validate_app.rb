require 'dry/cli'
require 'cfpropertylist'
require 'zip'

module EmergeCLI
  module Commands
    class ValidateApp < EmergeCLI::Commands::GlobalOptions
      desc 'Validate app for build distribution'

      option :path, type: :string, required: true, desc: 'Path to the xcarchive or IPA to validate'

      # Constants
      PLIST_START = '<plist'.freeze
      PLIST_STOP = '</plist>'.freeze

      UTF8_ENCODING = 'UTF-8'.freeze
      STRING_FORMAT = 'binary'.freeze
      EMPTY_STRING = ''.freeze

      def call(**options)
        @options = options
        before(options)

        Sync do
          file_extension = File.extname(@options[:path])
          case file_extension
          when '.xcarchive'
            handle_xcarchive
          when '.ipa'
            handle_ipa
          when '.app'
            handle_app
          else
            raise 'Unknown file extension'
          end
        end
      end

      private

      def handle_xcarchive
        raise 'Path must be an xcarchive' unless @options[:path].end_with?('.xcarchive')

        app_path = Dir.glob("#{@options[:path]}/Products/Applications/*.app").first
        run_codesign_check(app_path)
        read_entitlements(app_path)
      end

      def handle_ipa
        raise 'Path must be an IPA' unless @options[:path].end_with?('.ipa')

        Dir.mktmpdir do |tmp_dir|
          Zip::File.open(@options[:path]) do |zip_file|
            zip_file.each do |entry|
              entry.extract(File.join(tmp_dir, entry.name))
            end
          end

          app_path = File.join(tmp_dir, 'Payload/*.app')
          app_path = Dir.glob(app_path).first
          run_codesign_check(app_path)
          read_entitlements(app_path)
        end
      end

      def handle_app
        raise 'Path must be an app' unless @options[:path].end_with?('.app')

        app_path = @options[:path]
        run_codesign_check(app_path)
        read_entitlements(app_path)
      end

      def run_codesign_check(app_path)
        command = "codesign -dvvv '#{app_path}'"
        Logger.debug command
        stdout, _, status = Open3.capture3(command)
        Logger.debug stdout
        raise '❌ Codesign check failed' unless status.success?

        Logger.info '✅ Codesign check passed'
      end

      def read_entitlements(app_path)
        entitlements_path = File.join(app_path, 'embedded.mobileprovision')
        raise '❌ Entitlements file not found' unless File.exist?(entitlements_path)

        content = File.read(entitlements_path)
        lines = content.lines

        buffer = ''
        inside_plist = false
        lines.each do |line|
          inside_plist = true if line.include? PLIST_START
          if inside_plist
            buffer << line
            break if line.include? PLIST_STOP
          end
        end

        encoded_plist = buffer.encode(UTF8_ENCODING, STRING_FORMAT, invalid: :replace, undef: :replace,
                                                                    replace: EMPTY_STRING)
        encoded_plist = encoded_plist.sub(/#{PLIST_STOP}.+/, PLIST_STOP)

        plist = CFPropertyList::List.new(data: encoded_plist)
        parsed_data = CFPropertyList.native_types(plist.value)

        expiration_date = parsed_data['ExpirationDate']
        if expiration_date > Time.now
          Logger.info '✅ Provisioning profile hasn\'t expired'
        else
          Logger.info '❌ Provisioning profile is expired'
        end

        provisions_all_devices = parsed_data['ProvisionsAllDevices']
        if provisions_all_devices
          Logger.info 'Provisioning profile supports all devices (likely an enterprise profile)'
        else
          devices = parsed_data['ProvisionedDevices']
          Logger.info 'Provisioning profile does not support all devices (likely a development profile).'
          Logger.info "Devices: #{devices.inspect}"
        end
      end
    end
  end
end
