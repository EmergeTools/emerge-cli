require 'open3'

module EmergeCLI
  module Git
    def self.branch
      Logger.debug 'Getting current branch name'
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
      Logger.debug 'Getting current SHA'
      command = 'git rev-parse HEAD'
      Logger.debug command
      stdout, _, status = Open3.capture3(command)
      stdout.strip if status.success?
    end

    def self.base_sha
      Logger.debug 'Getting base SHA'
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
      Logger.debug 'Getting previous SHA'
      
      # First, determine if we're in a PR context
      pr_branch = ENV['GITHUB_HEAD_REF']
      base_branch = ENV['GITHUB_BASE_REF']
      
      if pr_branch && base_branch
        # We're in a PR context
        Logger.debug "PR context detected: #{pr_branch} → #{base_branch}"
        
        # For PR, get the immediate parent of HEAD in the PR branch
        command = 'git log -n 3 --pretty=format:"%H" HEAD'
        Logger.debug command
        stdout, stderr, status = Open3.capture3(command)
        
        if status.success?
          shas = stdout.strip.split("\n")
          return shas[2] if shas.length > 2
        else
          Logger.error "Failed to get previous PR SHA: #{stderr}"
        end
      else
        # Not in PR context, your regular logic
        command = 'git rev-list --count HEAD'
        Logger.debug command
        count_stdout, _, count_status = Open3.capture3(command)
    
        if !count_status.success? || count_stdout.strip.to_i <= 1
          Logger.error 'Detected shallow clone while trying to get the previous commit. ' \
                       'Please clone with full history using: git clone --no-single-branch ' \
                       'or configure CI with fetch-depth: 0'
          return nil
        end
    
        command = 'git rev-parse HEAD^'
        Logger.debug command
        stdout, stderr, status = Open3.capture3(command)
        Logger.error "Failed to get previous SHA: #{stdout}, #{stderr}" if !status.success?
        return stdout.strip if status.success?
      end
      
      nil
    end

    def self.primary_remote
      Logger.debug 'Getting primary remote'
      remote = remote()
      return nil if remote.nil?
      remote.include?('origin') ? 'origin' : remote.first
    end

    def self.remote_head_branch(remote = primary_remote)
      Logger.debug 'Getting remote head branch'
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
      Logger.debug 'Getting remote URL'
      return nil if remote.nil?
      command = "git config --get remote.#{remote}.url"
      Logger.debug command
      stdout, _, status = Open3.capture3(command)
      stdout if status.success?
    end

    def self.remote
      Logger.debug 'Getting remote'
      command = 'git remote'
      Logger.debug command
      stdout, _, status = Open3.capture3(command)
      stdout.split("\n") if status.success?
    end
  end
end
