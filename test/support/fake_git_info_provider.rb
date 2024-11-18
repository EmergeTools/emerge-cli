module EmergeCLI
  class FakeGitInfoProvider
    def initialize(git_result)
      @git_result = git_result
    end

    def fetch_git_info
      @git_result
    end
  end
end
