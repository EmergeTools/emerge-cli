require 'dry/cli'
require 'xcodeproj'

module EmergeCLI
  module Commands
    module Fix
      class StripBinarySymbols < EmergeCLI::Commands::GlobalOptions
        desc 'Strip binary symbols from the app'

        option :path, type: :string, required: true, desc: 'Path to the xcarchive'

        # Constants
        SCRIPT_NAME = 'EmergeTools Strip Binary Symbols'.freeze
        ENABLE_USER_SCRIPT_SANDBOXING = 'ENABLE_USER_SCRIPT_SANDBOXING'.freeze
        INPUT_FILE = '${DWARF_DSYM_FOLDER_PATH}/${EXECUTABLE_NAME}.app.dSYM/' \
                     'Contents/Resources/DWARF/${EXECUTABLE_NAME}'.freeze
        SCRIPT_CONTENT = %{#!/bin/bash
set -e

echo "Starting the symbol stripping process..."

if [ "Release" = "$\{CONFIGURATION\}" ]; then
  echo "Configuration is Release."

  # Path to the app directory
  APP_DIR_PATH="$\{BUILT_PRODUCTS_DIR\}/$\{EXECUTABLE_FOLDER_PATH\}"
  echo "App directory path: $\{APP_DIR_PATH\}"

  # Strip main binary
  echo "Stripping main binary: $\{APP_DIR_PATH\}/$\{EXECUTABLE_NAME\}"
  strip -rSTx "$\{APP_DIR_PATH\}/$\{EXECUTABLE_NAME\}"
  if [ $? -eq 0 ]; then
    echo "Successfully stripped main binary."
  else
    echo "Failed to strip main binary." >&2
  fi

  # Path to the Frameworks directory
  APP_FRAMEWORKS_DIR="$\{APP_DIR_PATH\}/Frameworks"
  echo "Frameworks directory path: $\{APP_FRAMEWORKS_DIR\}"

  # Strip symbols from frameworks, if Frameworks/ exists at all
  # ... as long as the framework is NOT signed by Apple
  if [ -d "$\{APP_FRAMEWORKS_DIR\}" ]; then
    echo "Frameworks directory exists. Proceeding to strip symbols from frameworks."
    find "$\{APP_FRAMEWORKS_DIR\}" -type f -perm +111 -maxdepth 2 -mindepth 2 -exec bash -c '
    codesign -v -R="anchor apple" "\{\}" &> /dev/null ||
    (
        echo "Stripping \{\}" &&
        if [ -w "\{\}" ]; then
            strip -rSTx "\{\}"
            if [ $? -eq 0 ]; then
                echo "Successfully stripped \{\}"
            else
                echo "Failed to strip \{\}" >&2
            fi
        else
            echo "Warning: No write permission for \{\}"
        fi
    )
    ' \\;
    if [ $? -eq 0 ]; then
        echo "Successfully stripped symbols from frameworks."
    else
        echo "Failed to strip symbols from some frameworks." >&2
    fi
  else
    echo "Frameworks directory does not exist. Skipping framework stripping."
  fi
else
  echo "Configuration is not Release. Skipping symbol stripping."
fi

echo "Symbol stripping process completed."}.freeze

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

        def add_run_script(target)
          phase = target.shell_script_build_phases.find { |item| item.name == SCRIPT_NAME }
          return unless phase.nil?
          Logger.info "Creating script '#{SCRIPT_NAME}'"
          phase = target.new_shell_script_build_phase(SCRIPT_NAME)
          phase.shell_script = SCRIPT_CONTENT
          phase.input_paths = [INPUT_FILE]
        end
      end
    end
  end
end
