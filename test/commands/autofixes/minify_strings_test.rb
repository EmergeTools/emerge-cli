require 'test_helper'

module EmergeCLI
  module Commands
    module Autofixes
      class MinifyStringsTest < Minitest::Test
        SCRIPT_NAME = 'EmergeTools Minify Strings'.freeze
        ENABLE_USER_SCRIPT_SANDBOXING = 'ENABLE_USER_SCRIPT_SANDBOXING'.freeze
        STRINGS_FILE_OUTPUT_ENCODING = 'STRINGS_FILE_OUTPUT_ENCODING'.freeze
        STRINGS_FILE_OUTPUT_ENCODING_VALUE = 'UTF-8'.freeze

        def setup
          @command = EmergeCLI::Commands::Autofixes::MinifyStrings.new

          FileUtils.mkdir_p('tmp/test_autofix_strings')
          FileUtils.cp_r('test/test_files/ExampleApp.xcodeproj', 'tmp/test_autofix_strings/ExampleApp.xcodeproj')
        end

        def teardown
          FileUtils.rm_rf('tmp/test_autofix_strings')
        end

        def test_script_is_created
          options = {
            path: 'tmp/test_autofix_strings/ExampleApp.xcodeproj'
          }

          @command.call(**options)

          project = Xcodeproj::Project.open('tmp/test_autofix_strings/ExampleApp.xcodeproj')

          phase = project.targets[0].shell_script_build_phases.find do |item|
            item.name == SCRIPT_NAME
          end
          assert_equal SCRIPT_NAME, phase.name
        end

        def test_user_script_sandboxing_is_disabled
          options = {
            path: 'tmp/test_autofix_strings/ExampleApp.xcodeproj'
          }

          @command.call(**options)

          project = Xcodeproj::Project.open('tmp/test_autofix_strings/ExampleApp.xcodeproj')

          project.targets[0].build_configurations.each do |config|
            assert_equal 'NO', config.build_settings[ENABLE_USER_SCRIPT_SANDBOXING]
          end
        end

        def test_strings_encoding_is_utf8
          options = {
            path: 'tmp/test_autofix_strings/ExampleApp.xcodeproj'
          }

          @command.call(**options)

          project = Xcodeproj::Project.open('tmp/test_autofix_strings/ExampleApp.xcodeproj')

          project.targets[0].build_configurations.each do |config|
            assert_equal STRINGS_FILE_OUTPUT_ENCODING_VALUE, config.build_settings[STRINGS_FILE_OUTPUT_ENCODING]
          end
        end
      end
    end
  end
end
