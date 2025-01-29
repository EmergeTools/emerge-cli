require 'dry/cli'
require 'cfpropertylist'

module EmergeCLI
  module Commands
    module OrderFiles
      class ValidateLinkmaps < EmergeCLI::Commands::GlobalOptions
        desc 'Validate linkmaps in xcarchive'

        option :path, type: :string, required: true, desc: 'Path to the xcarchive to validate'

        def initialize(network: nil)
          @network = network
        end

        def call(**options)
          @options = options
          before(options)

          Sync do
            executable_name = get_executable_name
            raise 'Executable not found' if executable_name.nil?

            Logger.info "Using executable: #{executable_name}"

            linkmaps_path = File.join(@options[:path], 'Linkmaps')
            raise 'Linkmaps folder not found' unless File.directory?(linkmaps_path)

            linkmaps = Dir.glob("#{linkmaps_path}/*.txt")
            raise 'No linkmaps found' if linkmaps.empty?

            executable_linkmaps = linkmaps.select do |linkmap|
              File.basename(linkmap).start_with?(executable_name)
            end
            raise 'No linkmaps found for executable' if executable_linkmaps.empty?

            Logger.info "✅ Found linkmaps for #{executable_name}"
          end
        end

        private

        def get_executable_name
          raise 'Path must be an xcarchive' unless @options[:path].end_with?('.xcarchive')

          app_path = Dir.glob("#{@options[:path]}/Products/Applications/*.app").first
          info_path = File.join(app_path, 'Info.plist')
          plist_data = File.read(info_path)
          plist = CFPropertyList::List.new(data: plist_data)
          parsed_data = CFPropertyList.native_types(plist.value)

          parsed_data['CFBundleExecutable']
        end
      end
    end
  end
end
