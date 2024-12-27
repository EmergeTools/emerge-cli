require 'test_helper'

module EmergeCLI
  module Commands
    module Autofixes
      class ExportedSymbolsTest < Minitest::Test
        EMERGE_TOOLS_GROUP = 'EmergeToolsHelperFiles'.freeze
        EXPORTED_SYMBOLS_FILE = 'EXPORTED_SYMBOLS_FILE'.freeze
        EXPORTED_SYMBOLS_PATH = '$(SRCROOT)/EmergeToolsHelperFiles/ExportedSymbols'.freeze
        DEFAULT_EXPORTED_SYMBOLS = %(_main
__mh_execute_header).freeze

        def setup
          @command = EmergeCLI::Commands::Autofixes::ExportedSymbols.new

          FileUtils.mkdir_p('tmp/test_autofix_exported_symbols')
          FileUtils.cp_r('test/test_files/ExampleApp.xcodeproj',
                         'tmp/test_autofix_exported_symbols/ExampleApp.xcodeproj')
        end

        def teardown
          FileUtils.rm_rf('tmp/test_autofix_exported_symbols')
        end

        def test_exported_symbols_is_set
          options = {
            path: 'tmp/test_autofix_exported_symbols/ExampleApp.xcodeproj'
          }

          @command.call(**options)

          project = Xcodeproj::Project.open('tmp/test_autofix_exported_symbols/ExampleApp.xcodeproj')
          group = project.main_group

          emergetools_group = group.find_subpath(EMERGE_TOOLS_GROUP, false)
          assert !emergetools_group.nil?

          project.targets[0].build_configurations.each do |config|
            assert_equal EXPORTED_SYMBOLS_PATH, config.build_settings[EXPORTED_SYMBOLS_FILE]
          end

          file_path = 'tmp/test_autofix_exported_symbols/EmergeToolsHelperFiles/ExportedSymbols'
          assert File.exist?(file_path)
          assert_equal DEFAULT_EXPORTED_SYMBOLS, File.read(file_path)
        end
      end
    end
  end
end
