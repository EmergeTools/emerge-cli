module EmergeCLI
  class GitInfoProvider
    def fetch_git_info
      if EmergeCLI::Github.supported_github_event?
        Logger.info 'Fetching Git info from Github event'
        EmergeCLI::GitResult.new(
          sha: EmergeCLI::Github.sha,
          base_sha: EmergeCLI::Github.base_sha,
          branch: EmergeCLI::Github.branch,
          pr_number: EmergeCLI::Github.pr_number,
          repo_name: EmergeCLI::Github.repo_name,
          previous_sha: EmergeCLI::Github.previous_sha
        )
      else
        Logger.info 'Fetching Git info from system Git'
        EmergeCLI::GitResult.new(
          sha: EmergeCLI::Git.sha,
          base_sha: EmergeCLI::Git.base_sha,
          branch: EmergeCLI::Git.branch,
          previous_sha: EmergeCLI::Git.previous_sha
        )
      end
    end
  end
end
