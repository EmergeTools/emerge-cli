module EmergeCLI
  class Environment
    def execute_command(command)
      `#{command}`
    end
  end
end
