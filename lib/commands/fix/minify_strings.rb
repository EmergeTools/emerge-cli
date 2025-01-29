require 'dry/cli'
require 'xcodeproj'

module EmergeCLI
  module Commands
    module Fix
      class MinifyStrings < EmergeCLI::Commands::GlobalOptions
        desc 'Minify strings in the app'

        option :path, type: :string, required: true, desc: 'Path to the xcarchive'

        # Constants
        SCRIPT_NAME = 'EmergeTools Minify Strings'.freeze
        ENABLE_USER_SCRIPT_SANDBOXING = 'ENABLE_USER_SCRIPT_SANDBOXING'.freeze
        STRINGS_FILE_OUTPUT_ENCODING = 'STRINGS_FILE_OUTPUT_ENCODING'.freeze
        STRINGS_FILE_OUTPUT_ENCODING_VALUE = 'UTF-8'.freeze
        SCRIPT_CONTENT = %{import os
import json
from multiprocessing.pool import ThreadPool

def minify(file_path):
  os.system(f"plutil -convert json '{file_path}'")
  new_content = ''
  try:
    with open(file_path, 'r') as input_file:
      data = json.load(input_file)

      for key, value in data.items():
        fixed_key = json.dumps(key, ensure_ascii=False).encode('utf8').decode()
        fixed_value = json.dumps(value, ensure_ascii=False).encode('utf8').decode()
        new_line = f'{fixed_key} = {fixed_value};\\n'
        new_content += new_line

    with open(file_path, 'w') as output_file:
      output_file.write(new_content)
  except:
    return

file_extension = '.strings'
stringFiles = []

for root, _, files in os.walk(os.environ['BUILT_PRODUCTS_DIR'], followlinks=True):
  for filename in files:
    if filename.endswith(file_extension):
      input_path = os.path.join(root, filename)
      stringFiles.append(input_path)

# create a thread pool
with ThreadPool() as pool:
  pool.map(minify, stringFiles)
}.freeze

        def call(**options)
          @options = options
          before(options)

          raise 'Path must be an xcodeproj' unless @options[:path].end_with?('.xcodeproj')
          raise 'Path does not exist' unless File.exist?(@options[:path])

          Sync do
            project = Xcodeproj::Project.open(@options[:path])

            project.targets.each do |target|
              target.build_configurations.each do |config|
                enable_user_script_sandboxing(config)
                set_output_encoding(config)
              end

              add_run_script(target)
            end

            project.save
          end
        end

        private

        def enable_user_script_sandboxing(config)
          Logger.info "Enabling user script sandboxing for #{config.name}"
          config.build_settings[ENABLE_USER_SCRIPT_SANDBOXING] = 'NO'
        end

        def set_output_encoding(config)
          Logger.info "Setting output encoding for #{config.name}"
          config.build_settings[STRINGS_FILE_OUTPUT_ENCODING] = STRINGS_FILE_OUTPUT_ENCODING_VALUE
        end

        def add_run_script(target)
          phase = target.shell_script_build_phases.find { |item| item.name == SCRIPT_NAME }
          return unless phase.nil?
          Logger.info "Creating script '#{SCRIPT_NAME}'"
          phase = target.new_shell_script_build_phase(SCRIPT_NAME)
          phase.shell_script = SCRIPT_CONTENT
          phase.shell_path = `which python3`.strip
        end
      end
    end
  end
end
