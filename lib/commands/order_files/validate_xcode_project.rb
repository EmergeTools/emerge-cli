require 'dry/cli'
require 'xcodeproj'

module EmergeCLI
  module Commands
    class ValidateXcodeProject < EmergeCLI::Commands::GlobalOptions
      desc 'Validate xcodeproject for order files'

      option :path, type: :string, required: true, desc: 'Path to the xcodeproject to validate'
      option :target, type: :string, required: false, desc: 'Target to validate'
      option :build_configuration, type: :string, required: false,
                                   desc: 'Build configuration to validate (Release by default)'

      # Constants
      LINK_MAPS_CONFIG = 'LD_GENERATE_MAP_FILE'.freeze
      LINK_MAPS_PATH = 'LD_MAP_FILE_PATH'.freeze
      PATH_TO_LINKMAP = '$(TARGET_TEMP_DIR)/$(PRODUCT_NAME)-LinkMap-$(CURRENT_VARIANT)-$(CURRENT_ARCH).txt'.freeze

      def call(**options)
        @options = options
        before(options)

        raise 'Path must be an xcodeproject' unless @options[:path].end_with?('.xcodeproj')
        raise 'Path does not exist' unless File.exist?(@options[:path])

        @options[:build_configuration] ||= 'Release'

        Sync do
          project = Xcodeproj::Project.open(@options[:path])

          validate_xcproj(project)
        end
      end

      private

      def validate_xcproj(project)
        project.targets.each do |target|
          next if @options[:target] && target.name != @options[:target]
          next unless target.product_type == 'com.apple.product-type.application'

          target.build_configurations.each do |config|
            next if config.name != @options[:build_configuration]
            validate_target_config(target, config)
          end
        end
      end

      def validate_target_config(target, config)
        has_error = false
        if config.build_settings[LINK_MAPS_CONFIG] != 'YES'
          has_error = true
          Logger.error "❌ Write Link Map File (#{LINK_MAPS_CONFIG}) is not set to YES"
        end
        if config.build_settings[LINK_MAPS_PATH] != ''
          has_error = true
          Logger.error "❌ Path to Link Map File (#{LINK_MAPS_PATH}) is not set, we recommend setting it to '#{PATH_TO_LINKMAP}'"
        end

        if has_error
          Logger.error "❌ Target '#{target.name}' has errors, this means \
that the linkmaps will not be generated as expected"
          Logger.error "Use `emerge configure order-files-ios --project-path '#{@options[:path]}'` to fix this"
        else
          Logger.info "✅ Target '#{target.name}' is valid"
        end
      end
    end
  end
end
