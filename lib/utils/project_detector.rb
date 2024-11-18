module EmergeCLI
  class ProjectDetector
    def initialize(project_path)
      @project_path = project_path
    end

    def ios_project?
      Dir.glob(File.join(@project_path, '*.{xcodeproj,xcworkspace}')).any?
    end
  end
end
