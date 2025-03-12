require 'dry/cli'

module EmergeCLI
  module Commands
    class Test < Dry::CLI::Command
      desc 'A simple test command that prints git info'

      option :fetch_depth, type: :integer, desc: 'Test with specific fetch depth (e.g. --fetch-depth=1)'

      def initialize
        @git_info_provider = EmergeCLI::GitInfoProvider.new
      end

      def call(**options)
        if options[:fetch_depth]
          EmergeCLI::Logger.info "Testing with fetch-depth=#{options[:fetch_depth]}..."
          system("git fetch --depth=#{options[:fetch_depth]}")
        end
        
        EmergeCLI::Logger.info "Testing git info..."
        git_result = @git_info_provider.fetch_git_info
        
        EmergeCLI::Logger.info "SHA: #{git_result.sha}"
        EmergeCLI::Logger.info "Branch: #{git_result.branch}"
        EmergeCLI::Logger.info "Base SHA: #{git_result.base_sha}"
        EmergeCLI::Logger.info "Previous SHA: #{git_result.previous_sha}"
        EmergeCLI::Logger.info "PR Number: #{git_result.pr_number}"
      end
    end
  end
end 