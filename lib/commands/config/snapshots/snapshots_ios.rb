require 'dry/cli'
require 'json'
require 'uri'
require 'chunky_png'
require 'async'
require 'async/barrier'
require 'async/semaphore'
require 'async/http/internet/instance'
require 'yaml'

require 'tty-prompt'
require 'tty-table'

module EmergeCLI
  module Commands
    module Config
      class SnapshotsIOS < EmergeCLI::Commands::GlobalOptions
        desc 'Configure snapshot testing for iOS'

        # Optional options
        option :interactive, type: :boolean, required: false,
                             desc: 'Run interactively'
        option :clear, type: :boolean, required: false, desc: 'Clear existing configuration'
        option :os_version, type: :string, required: true, desc: 'OS version'
        option :launch_arguments, type: :array, required: false, desc: 'Launch arguments to set'
        option :env_variables, type: :array, required: false, desc: 'Environment variables to set'
        option :exact_match_excluded_previews, type: :array, required: false, desc: 'Exact match excluded previews'
        option :regex_excluded_previews, type: :array, required: false, desc: 'Regex excluded previews'

        # Constants
        EXCLUDED_PREVIEW_PROMPT = 'Do you want to exclude any previews by exact match?'.freeze
        EXCLUDED_PREVIEW_FINISH_PROMPT = 'Enter the previews you want to exclude (leave blank to finish)'.freeze
        EXCLUDED_REGEX_PREVIEW_PROMPT = 'Do you want to exclude any previews by regex?'.freeze
        EXCLUDED_REGEX_PREVIEW_FINISH_PROMPT = 'Enter the previews you want to exclude (leave blank to finish)'.freeze
        ARGUMENTS_PROMPT = 'Do you want to set any arguments?'.freeze
        ARGUMENTS_FINISH_PROMPT = 'Enter the argument you want to set (leave blank to finish)'.freeze
        ENV_VARIABLES_PROMPT = 'Do you want to set any environment variables?'.freeze
        ENV_VARIABLES_FINISH_PROMPT = "Enter the environment variable you want to set (leave blank to finish) with \
format KEY=VALUE".freeze
        AVAILABLE_OS_VERSIONS = ['17.2', '17.5', '18.0'].freeze

        def initialize; end

        def call(**options)
          @options = options
          before(options)

          Sync do
            validate_options

            run_interactive_mode if @options[:interactive]

            run_non_interactive_mode if !@options[:interactive]

            Logger.warn 'Remember to copy `emerge_config.yml` to your project XCArchive before uploading it!'
          end
        end

        private

        def validate_options
          if @options[:interactive] && (!@options[:os_version].nil? || !@options[:launch_arguments].nil? ||
             !@options[:env_variables].nil? || !@options[:exact_match_excluded_previews].nil? ||
             !@options[:regex_excluded_previews].nil?)
            Logger.warn 'All options are ignored when using interactive mode'
          end
        end

        def run_interactive_mode
          prompt = TTY::Prompt.new

          override_config = false
          if File.exist?('emerge_config.yml')
            Logger.warn 'There is already a emerge_config.yml file.'
            prompt.yes?('Do you want to overwrite it?', default: false) do |answer|
              override_config = true if answer
            end
          end

          if !override_config && File.exist?('emerge_config.yml')
            config = YAML.load_file('emerge_config.yml')
            config['snapshots']['ios']['runSettings'] = []
          else
            config = {
              'version' => 2.0,
              'snapshots' => {
                'ios' => {
                  'runSettings' => []
                }
              }
            }
          end

          Logger.info 'Creating a new config file'

          end_config = false
          loop do
            os_version = get_os_version(prompt)

            excluded_previews = get_array_from_user(prompt, EXCLUDED_PREVIEW_PROMPT, EXCLUDED_PREVIEW_FINISH_PROMPT)
            excluded_regex_previews = get_array_from_user(prompt, EXCLUDED_REGEX_PREVIEW_PROMPT,
                                                          EXCLUDED_REGEX_PREVIEW_FINISH_PROMPT)
            arguments_array = get_array_from_user(prompt, ARGUMENTS_PROMPT, ARGUMENTS_FINISH_PROMPT)
            env_variables_array = get_array_from_user(prompt, ENV_VARIABLES_PROMPT, ENV_VARIABLES_FINISH_PROMPT)

            excluded = get_parsed_previews(excluded_previews, excluded_regex_previews)
            env_variables = get_parsed_env_variables(env_variables_array)

            os_settings = {
              'osVersion' => os_version,
              'excludedPreviews' => excluded,
              'envVariables' => env_variables,
              'arguments' => arguments_array
            }
            show_config(os_settings)
            save = prompt.yes?('Do you want to save this setting?')
            config['snapshots']['ios']['runSettings'].push(os_settings) if save

            end_config = !prompt.yes?('Do you want to continue adding more settings?')
            break if end_config
          end

          File.write('emerge_config.yml', config.to_yaml)
          Logger.info 'Configuration file created successfully!'
        end

        def run_non_interactive_mode
          config = {}
          if File.exist?('emerge_config.yml')
            config = YAML.load_file('emerge_config.yml')
            if !@options[:clear] && !config['snapshots'].nil? && !config['snapshots']['ios'].nil? &&
               !config['snapshots']['ios']['runSettings'].nil?
              raise 'There is already a configuration file with settings. Use the --clear flag to overwrite it.'
            end

            config['snapshots']['ios']['runSettings'] = []

          else
            config = {
              'version' => 2.0,
              'snapshots' => {
                'ios' => {
                  'runSettings' => []
                }
              }
            }
          end

          excluded_previews = get_parsed_previews(@options[:exact_match_excluded_previews] || [],
                                                  @options[:regex_excluded_previews] || [])
          env_variables = get_parsed_env_variables(@options[:env_variables] || [])

          os_version = @options[:os_version]
          if os_version.nil?
            Logger.warn 'No OS version was provided, defaulting to 17.5'
            os_version = '17.5'
          end

          os_settings = {
            'osVersion' => os_version,
            'excludedPreviews' => excluded_previews,
            'envVariables' => env_variables,
            'arguments' => @options[:launch_arguments] || []
          }
          config['snapshots']['ios']['runSettings'].push(os_settings)
          File.write('emerge_config.yml', config.to_yaml)
          Logger.info 'Configuration file created successfully!'
          show_config(os_settings)
        end

        def get_os_version(prompt)
          os_version = prompt.select('Select the OS version you want to run the tests on') do |answer|
            AVAILABLE_OS_VERSIONS.each do |version|
              answer.choice version, version.to_f
            end
            answer.choice 'Custom', 'custom'
          end
          os_version = prompt.ask('Enter the OS version you want to run the tests on') if os_version == 'custom'
          os_version
        end

        def get_array_from_user(prompt, first_prompt_message, second_prompt_message)
          continue = prompt.yes?(first_prompt_message)
          return [] if !continue
          array = []
          loop do
            item = prompt.ask(second_prompt_message)
            if item == '' || item.nil?
              continue = false
            else
              array.push(item)
            end
            break unless continue
          end
          array
        end

        def show_config(config)
          table = TTY::Table.new(
            header: %w[Key Value],
            rows: config.to_a
          )
          puts table.render(:ascii)
        end

        def get_parsed_previews(previews_exact, previews_regex)
          excluded = []
          previews_exact.each do |preview|
            excluded.push({
                            'type' => 'exact',
                            'value' => preview
                          })
          end
          previews_regex.each do |preview|
            excluded.push({
                            'type' => 'regex',
                            'value' => preview
                          })
          end
          excluded
        end

        def get_parsed_env_variables(env_variables)
          env_variables_array_fixed = []
          env_variables.each do |env_variable|
            key, value = env_variable.split('=')
            env_variables_array_fixed.push({
                                             'key' => key, 'value' => value
                                           })
          end
        end
      end
    end
  end
end
