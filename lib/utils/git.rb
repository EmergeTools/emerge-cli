require 'open3'

module EmergeCLI
  module Git
    def self.branch
      command = 'git rev-parse --abbrev-ref HEAD'
      Logger.debug command
      stdout, _, status = Open3.capture3(command)
      unless status.success?
        Logger.error 'Failed to get the current branch name'
        return nil
      end

      branch_name = stdout.strip
      if branch_name == 'HEAD'
        # We're in a detached HEAD state
        # Find all branches that contains the current HEAD commit
        #
        # Example output:
        # * (HEAD detached at dec13a5)
        # telkins/detached-test
        # remotes/origin/telkins/detached-test
        #
        # So far I've seen this output be fairly stable
        # If the input is invalid for whatever reason, sed/awk will return an empty string
        command = "git branch -a --contains HEAD | sed -n 2p | awk '{ printf $1 }'"
        Logger.debug command
        head_stdout, _, head_status = Open3.capture3(command)

        unless head_status.success?
          Logger.error 'Failed to get the current branch name for detached HEAD'
          return nil
        end

        branch_name = head_stdout.strip
      end

      branch_name == 'HEAD' ? nil : branch_name
    end

    def self.sha
      command = 'git rev-parse HEAD'
      Logger.debug command
      stdout, _, status = Open3.capture3(command)
      stdout.strip if status.success?
    end

    def self.base_sha
      current_branch = branch
      remote_head = remote_head_branch
      return nil if current_branch.nil? || remote_head.nil?

      command = "git merge-base #{remote_head} #{current_branch}"
      Logger.debug command
      stdout, _, status = Open3.capture3(command)
      return nil if stdout.strip.empty? || !status.success?
      current_sha = sha
      stdout.strip == current_sha ? nil : stdout.strip
    end

    def self.previous_sha
      command = 'git rev-list --count HEAD'
      Logger.debug command
      count_stdout, _, count_status = Open3.capture3(command)

      if !count_status.success? || count_stdout.strip.to_i <= 1
        Logger.error 'Detected shallow clone. Please clone with full history using: git clone --no-single-branch or configure CI with fetch-depth: 0'
        return nil
      end

      command = 'git rev-parse HEAD^'
      Logger.debug command
      stdout, stderr, status = Open3.capture3(command)
      Logger.error "Failed to get previous SHA: #{stdout}, #{stderr}" if !status.success?
      stdout.strip if status.success?
    end

    def self.primary_remote
      remote = remote()
      return nil if remote.nil?
      remote.include?('origin') ? 'origin' : remote.first
    end

    def self.remote_head_branch(remote = primary_remote)
      return nil if remote.nil?
      command = "git remote show #{remote}"
      Logger.debug command
      stdout, _, status = Open3.capture3(command)
      return nil if stdout.nil? || !status.success?
      stdout
        .split("\n")
        .map(&:strip)
        .find { |line| line.start_with?('HEAD branch: ') }
        &.split
        &.last
    end

    def self.remote_url(remote = primary_remote)
      return nil if remote.nil?
      command = "git config --get remote.#{remote}.url"
      Logger.debug command
      stdout, _, status = Open3.capture3(command)
      stdout if status.success?
    end

    def self.remote
      command = 'git remote'
      Logger.debug command
      stdout, _, status = Open3.capture3(command)
      stdout.split("\n") if status.success?
    end
  end
end
