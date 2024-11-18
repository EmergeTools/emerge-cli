module EmergeCLI
  module Github
    GITHUB_EVENT_PR = 'pull_request'.freeze
    GITHUB_EVENT_PUSH = 'push'.freeze

    def self.event_name
      ENV['GITHUB_EVENT_NAME']
    end

    def self.supported_github_event?
      Logger.info "GitHub event name: #{event_name}"
      pull_request? || push?
    end

    def self.pull_request?
      event_name == GITHUB_EVENT_PR
    end

    def self.push?
      event_name == GITHUB_EVENT_PUSH
    end

    def self.sha
      if push?
        ENV['GITHUB_SHA']
      elsif pull_request?
        github_event_data.dig(:pull_request, :head, :sha)
      end
    end

    def self.base_sha
      return unless pull_request?
      github_event_data.dig(:pull_request, :base, :sha)
    end

    def self.pr_number
      pull_request? ? github_event_data[:number] : nil
    end

    def self.branch
      pull_request? ? github_event_data.dig(:pull_request, :head, :ref) : Git.branch
    end

    def self.repo_owner
      github_event_data.dig(:repository, :owner, :login)
    end

    def self.repo_name
      github_event_data.dig(:repository, :full_name)
    end

    def self.previous_sha
      Git.previous_sha
    end

    def self.github_event_data
      @github_event_data ||= begin
        github_event_path = ENV['GITHUB_EVENT_PATH']
        Logger.error 'GITHUB_EVENT_PATH is not set' if github_event_path.nil?

        Logger.error "File #{github_event_path} doesn't exist" unless File.exist?(github_event_path)

        file_content = File.read(github_event_path)
        file_json = JSON.parse(file_content, symbolize_names: true)
        Logger.debug "Parsed GitHub event data: #{file_json.inspect}"

        file_json
      end
    end
  end
end
