require 'test_helper'

module EmergeCLI
  module Commands
    module Config
      class OrderFilesIOSTest < Minitest::Test
        LINK_MAPS_CONFIG = 'LD_GENERATE_MAP_FILE'.freeze
        LINK_MAPS_PATH = 'LD_MAP_FILE_PATH'.freeze
        PATH_TO_LINKMAP = '$(TARGET_TEMP_DIR)/$(PRODUCT_NAME)-LinkMap-$(CURRENT_VARIANT)-$(CURRENT_ARCH).txt'.freeze
        ORDER_FILE = 'ORDER_FILE'.freeze
        ORDER_FILE_PATH = '$(PROJECT_DIR)/orderfiles/orderfile.txt'.freeze

        def setup
          @command = EmergeCLI::Commands::Config::OrderFilesIOS.new

          FileUtils.mkdir_p('tmp/test_orderfiles')
          FileUtils.cp_r('test/test_files/ExampleApp.xcodeproj', 'tmp/test_orderfiles/ExampleApp.xcodeproj')
        end

        def teardown
          FileUtils.rm_rf('tmp/test_orderfiles')
        end

        def test_linkmaps_are_enabled_and_orderfiles_are_downloaded
          options = {
            project_path: 'tmp/test_orderfiles/ExampleApp.xcodeproj'
          }

          @command.call(**options)

          project = Xcodeproj::Project.open('tmp/test_orderfiles/ExampleApp.xcodeproj')

          project.targets[0].build_configurations.each do |config|
            assert_equal PATH_TO_LINKMAP, config.build_settings[LINK_MAPS_PATH]
            assert_equal 'YES', config.build_settings[LINK_MAPS_CONFIG]
            assert_equal ORDER_FILE_PATH, config.build_settings[ORDER_FILE]
          end

          phase = project.targets[0].shell_script_build_phases.find { |item| item.name == 'Download Order Files' }
          assert_equal ORDER_FILE_PATH, phase.output_paths[0]
        end

        def test_linkmaps_are_enabled_only
          options = {
            project_path: 'tmp/test_orderfiles/ExampleApp.xcodeproj',
            only_enable_linkmaps: true
          }

          @command.call(**options)

          project = Xcodeproj::Project.open('tmp/test_orderfiles/ExampleApp.xcodeproj')

          project.targets[0].build_configurations.each do |config|
            assert_equal PATH_TO_LINKMAP, config.build_settings[LINK_MAPS_PATH]
            assert_equal 'YES', config.build_settings[LINK_MAPS_CONFIG]
            refute_equal ORDER_FILE_PATH, config.build_settings[ORDER_FILE]
          end

          phase = project.targets[0].shell_script_build_phases.find { |item| item.name == 'Download Order Files' }
          assert_nil phase
        end
      end
    end
  end
end
