require 'test_helper'

module EmergeCLI
  module Commands
    module Autofixes
      class StripBinarySymbolsTest < Minitest::Test
        SCRIPT_NAME = 'EmergeTools Strip Binary Symbols'.freeze
        ENABLE_USER_SCRIPT_SANDBOXING = 'ENABLE_USER_SCRIPT_SANDBOXING'.freeze
        INPUT_FILE = '${DWARF_DSYM_FOLDER_PATH}/${EXECUTABLE_NAME}.app.dSYM/' \
                     'Contents/Resources/DWARF/${EXECUTABLE_NAME}'.freeze

        def setup
          @command = EmergeCLI::Commands::Autofixes::StripBinarySymbols.new

          FileUtils.mkdir_p('tmp/test_autofix_strip_binary_symbols')
          FileUtils.cp_r('test/test_files/ExampleApp.xcodeproj',
                         'tmp/test_autofix_strip_binary_symbols/ExampleApp.xcodeproj')
        end

        def teardown
          FileUtils.rm_rf('tmp/test_autofix_strip_binary_symbols')
        end

        def test_script_is_created
          options = {
            path: 'tmp/test_autofix_strip_binary_symbols/ExampleApp.xcodeproj'
          }

          @command.call(**options)

          project = Xcodeproj::Project.open('tmp/test_autofix_strip_binary_symbols/ExampleApp.xcodeproj')

          phase = project.targets[0].shell_script_build_phases.find do |item|
            item.name == SCRIPT_NAME
          end
          assert_equal SCRIPT_NAME, phase.name
          assert_equal INPUT_FILE, phase.input_paths[0]
        end

        def test_user_script_sandboxing_is_disabled
          options = {
            path: 'tmp/test_autofix_strip_binary_symbols/ExampleApp.xcodeproj'
          }

          @command.call(**options)

          project = Xcodeproj::Project.open('tmp/test_autofix_strip_binary_symbols/ExampleApp.xcodeproj')

          project.targets[0].build_configurations.each do |config|
            assert_equal 'NO', config.build_settings[ENABLE_USER_SCRIPT_SANDBOXING]
          end
        end
      end
    end
  end
end
