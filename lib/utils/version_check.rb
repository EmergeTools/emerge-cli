require 'json'

module EmergeCLI
  module Utils
    class VersionCheck
      def initialize(network: EmergeCLI::Network.new)
        @network = network
      end

      def check_version
        begin
          Sync do
            response = @network.get(
              path: 'https://rubygems.org/api/v1/gems/emerge.json',
              headers: {}
            )
            latest_version = JSON.parse(response.read).fetch('version')
            current_version = EmergeCLI::VERSION

            if Gem::Version.new(latest_version) > Gem::Version.new(current_version)
              Logger.warn "A new version of emerge-cli is available (#{latest_version})"
              Logger.warn "You are currently using version #{current_version}"
              Logger.warn "To update, run: gem update emerge\n"
            end
          end
        rescue KeyError => e
          Logger.error "Failed to parse version from RubyGems API response"
        rescue => e
          Logger.error "Failed to check for updates: #{e.message}"
        end
      end
    end
  end
end
