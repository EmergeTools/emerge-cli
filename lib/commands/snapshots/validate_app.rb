require 'dry/cli'
require 'json'
require 'uri'
require 'yaml'
require 'cfpropertylist'

module EmergeCLI
  module Commands
    module Snapshots
      class ValidateApp < EmergeCLI::Commands::GlobalOptions
        desc 'Validate app for snapshot testing [iOS, macOS]'

        # Optional options
        option :path, type: :string, required: true, desc: 'Path to the app binary or xcarchive'

        # Mangled names are deterministic, no need to demangle them
        SWIFT_PREVIEWS_MANGLED_NAMES = [
          '_$s21DeveloperToolsSupport15PreviewRegistryMp',
          '_$s7SwiftUI15PreviewProviderMp'
        ].freeze

        def call(**options)
          @options = options
          before(options)

          Sync do
            binary_path = get_binary_path
            Logger.info "Found binary: #{binary_path}"

            Logger.info "Loading binary: #{binary_path}"
            macho_parser = MachOParser.new
            macho_parser.load_binary(binary_path)

            use_chained_fixups, imported_symbols = macho_parser.read_linkedit_data_command
            bound_symbols = macho_parser.read_dyld_info_only_command

            found = macho_parser.find_protocols_in_swift_proto(use_chained_fixups, imported_symbols, bound_symbols,
                                                               SWIFT_PREVIEWS_MANGLED_NAMES)

            if found
              Logger.info '✅ Found SwiftUI previews'
            else
              Logger.error '❌ No SwiftUI previews found'
            end
            found
          end
        end

        private

        def get_binary_path
          return @options[:path] unless @options[:path].end_with?('.xcarchive')
          app_path = Dir.glob("#{@options[:path]}/Products/Applications/*.app").first
          info_path = File.join(app_path, 'Info.plist')
          plist_data = File.read(info_path)
          plist = CFPropertyList::List.new(data: plist_data)
          parsed_data = CFPropertyList.native_types(plist.value)

          File.join(app_path, parsed_data['CFBundleExecutable'])
        end
      end
    end
  end
end
