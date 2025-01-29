require 'dry/cli'
require 'xcodeproj'

module EmergeCLI
  module Commands
    module Fix
      class ExportedSymbols < EmergeCLI::Commands::GlobalOptions
        desc 'Remove exported symbols from built binaries'

        option :path, type: :string, required: true, desc: 'Path to the xcarchive'

        # Constants
        DEFAULT_EXPORTED_SYMBOLS = %(_main
__mh_execute_header).freeze
        EXPORTED_SYMBOLS_FILE = 'EXPORTED_SYMBOLS_FILE'.freeze
        EXPORTED_SYMBOLS_PATH = '$(SRCROOT)/EmergeToolsHelperFiles/ExportedSymbols'.freeze
        EXPORTED_SYMBOLS_FILE_NAME = 'ExportedSymbols'.freeze
        EMERGE_TOOLS_GROUP = 'EmergeToolsHelperFiles'.freeze

        def call(**options)
          @options = options
          before(options)

          raise 'Path must be an xcodeproj' unless @options[:path].end_with?('.xcodeproj')
          raise 'Path does not exist' unless File.exist?(@options[:path])

          Sync do
            project = Xcodeproj::Project.open(@options[:path])

            # Add the exported symbols file to the project
            group = project.main_group
            emergetools_group = group.find_subpath(EMERGE_TOOLS_GROUP, true)
            emergetools_group.set_path(EMERGE_TOOLS_GROUP)

            unless emergetools_group.find_file_by_path(EXPORTED_SYMBOLS_FILE_NAME)
              emergetools_group.new_file(EXPORTED_SYMBOLS_FILE_NAME)
            end

            # Create Folder if it doesn't exist

            FileUtils.mkdir_p(File.join(File.dirname(@options[:path]), EMERGE_TOOLS_GROUP))

            # Create the exported symbols file
            path = File.join(File.dirname(@options[:path]), EMERGE_TOOLS_GROUP, EXPORTED_SYMBOLS_FILE_NAME)
            File.write(path, DEFAULT_EXPORTED_SYMBOLS)

            project.targets.each do |target|
              # Only do it for app targets
              next unless target.product_type == 'com.apple.product-type.application'

              target.build_configurations.each do |config|
                config.build_settings[EXPORTED_SYMBOLS_FILE] = EXPORTED_SYMBOLS_PATH
              end
            end

            project.save
          end
        end
      end
    end
  end
end
