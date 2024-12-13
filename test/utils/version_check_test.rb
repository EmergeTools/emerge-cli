require 'test_helper'

module EmergeCLI
  module Utils
    class VersionCheckTest < Minitest::Test
      def setup
        @network = FakeNetwork.new
        @version_check = VersionCheck.new(network: @network)
      end

      def test_warns_when_newer_version_available
        @network = FakeNetwork.new(
          'https://rubygems.org/api/v1/gems/emerge.json' => '{"version": "999.0.0"}'
        )
        @version_check = VersionCheck.new(network: @network)

        Logger.stub :warn, ->(msg) { @captured_warnings ||= []; @captured_warnings << msg } do
          @version_check.check_version
        end

        assert_equal 3, @captured_warnings.length
        assert_match /A new version of emerge-cli is available \(999.0.0\)/, @captured_warnings[0]
        assert_match /You are currently using version #{EmergeCLI::VERSION}/, @captured_warnings[1]
        assert_match /To update, run: gem update emerge/, @captured_warnings[2]
      end

      def test_silent_when_current_version
        @network = FakeNetwork.new(
          'https://rubygems.org/api/v1/gems/emerge.json' => "{\"version\": \"#{EmergeCLI::VERSION}\"}"
        )
        @version_check = VersionCheck.new(network: @network)

        Logger.stub :warn, ->(_msg) { flunk "Should not warn when version is current" } do
          @version_check.check_version
        end
      end

      def test_logs_error_when_version_key_missing
        @network = FakeNetwork.new(
          'https://rubygems.org/api/v1/gems/emerge.json' => '{}'
        )
        @version_check = VersionCheck.new(network: @network)

        Logger.stub :error, ->(msg) { @error_message = msg } do
          @version_check.check_version
        end

        assert_equal "Failed to parse version from RubyGems API response", @error_message
      end
    end
  end
end
