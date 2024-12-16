require 'dry/cli'
require 'logger'

module EmergeCLI
  module Commands
    class GlobalOptions < Dry::CLI::Command
      option :debug, type: :boolean, default: false, desc: 'Enable debug logging'

      def before(args)
        log_level = args[:debug] ? ::Logger::DEBUG : ::Logger::INFO
        EmergeCLI::Logger.configure(log_level)

        EmergeCLI::Utils::VersionCheck.new.check_version
      end
    end
  end
end
