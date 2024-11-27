require 'test_helper'

module EmergeCLI
  module Commands
    module Config
      class SnapshotsIOSTest < Minitest::Test
        def setup
          @command = EmergeCLI::Commands::Config::SnapshotsIOS.new
        end

        def teardown
          FileUtils.rm_rf('emerge_config.yml')
        end

        def test_raises_error_if_no_clear_and_config_exists
          File.write('emerge_config.yml', {}.to_yaml)

          options = {}

          assert_raises(Exception) do
            @command.call(**options)
          end
        end

        def test_creates_config_if_no_config_exists
          options = {}

          @command.call(**options)

          assert File.exist?('emerge_config.yml')

          full_config = YAML.load_file('emerge_config.yml')
          snapshot_config = full_config['snapshots']['ios']['runSettings'][0]
          assert_equal '17.5', snapshot_config['osVersion']
          assert_equal [], snapshot_config['arguments']
          assert_equal [], snapshot_config['envVariables']
          assert_equal [], snapshot_config['excludedPreviews']
        end

        def test_config_is_updated_if_config_exists
          previous_config = {
            'snapshots' => {
              'ios' => {
                'runSettings' => [{ 'osVersion' => '17.5' }]
              }
            }
          }
          File.write('emerge_config.yml', previous_config.to_yaml)

          options = {
            os_version: '18.0',
            launch_arguments: %w[arg1 arg2],
            clear: true
          }

          @command.call(**options)

          assert File.exist?('emerge_config.yml')

          full_config = YAML.load_file('emerge_config.yml')
          snapshot_config = full_config['snapshots']['ios']['runSettings'][0]
          assert_equal '18.0', snapshot_config['osVersion']
          assert_equal %w[arg1 arg2], snapshot_config['arguments']
          assert_equal [], snapshot_config['envVariables']
          assert_equal [], snapshot_config['excludedPreviews']
        end
      end
    end
  end
end
