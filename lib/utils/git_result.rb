module EmergeCLI
  class GitResult
    attr_accessor :sha, :base_sha, :previous_sha, :branch, :pr_number, :repo_name

    def initialize(sha:, base_sha:, branch:, pr_number: nil, repo_name: nil, previous_sha: nil)
      @pr_number = pr_number
      @sha = sha
      @base_sha = base_sha
      @previous_sha = previous_sha
      @branch = branch
      @repo_name = repo_name
    end
  end
end
