require 'xcodeproj'

module EmergeCLI
  module Commands
    module Config
      class OrderFilesIOS < EmergeCLI::Commands::GlobalOptions
        desc 'Configure order files for iOS'

        # Optional options
        option :only_enable_linkmaps, type: :boolean, required: false, desc: 'Only enable linkmaps'
        option :project_path, type: :string, required: false, desc: 'Path to the xcode project (will use first found if not provided)'

        # Constants
        LINK_MAPS_CONFIG = 'LD_GENERATE_MAP_FILE'.freeze
        LINK_MAPS_PATH = 'LD_MAP_FILE_PATH'.freeze
        PATH_TO_LINKMAP = '$(TARGET_TEMP_DIR)/$(PRODUCT_NAME)-LinkMap-$(CURRENT_VARIANT)-$(CURRENT_ARCH).txt'.freeze
        ORDER_FILE = "ORDER_FILE".freeze

        def initialize; end

        def call(**options)
          @options = options
          before(options)

          if @options[:project_path]
            project = Xcodeproj::Project.open(@options[:project_path])
          else
            project = Xcodeproj::Project.open(Dir.glob('*.xcodeproj').first)
            Logger.warn 'No project path provided, using first found xcodeproj in current directory'
          end

          enable_linkmaps(project)

          add_order_files_download_script(project) unless @options[:only_enable_linkmaps]
          
          project.save
        end

        private

        def enable_linkmaps(project)
          Logger.info "Enabling Linkmaps"
          project.targets.each do |target|
            # Only do it for app targets
            next unless target.product_type == 'com.apple.product-type.application'

            Logger.info "  Target: #{target.name}"
            target.build_configurations.each do |config|
              config.build_settings[LINK_MAPS_CONFIG] = 'YES'
              config.build_settings[LINK_MAPS_PATH] = PATH_TO_LINKMAP
            end
          end
        end

        def add_order_files_download_script(project)
          Logger.info "Adding order files download script"
          project.targets.each do |target|
            # Only do it for app targets
            next unless target.product_type == 'com.apple.product-type.application'

            Logger.info "  Target: #{target.name}"

            # Create the script phase if it doesn't exist
            phase = target.shell_script_build_phases().find {|item| item.name == "Download Order Files"}
            if (phase.nil?)
                Logger.info "  Creating script 'Download Order Files'"
                phase = target.new_shell_script_build_phase("Download Order Files")
                phase.shell_script = "\
if [ \"$CONFIGURATION\" != \"Release\" ]; then
  echo \"Skipping script for non-Release build\"
  exit 0
fi

if curl --fail \"https://order-files-prod.emergetools.com/$PRODUCT_BUNDLE_IDENTIFIER/$MARKETING_VERSION\" -H \"X-API-Token: $EMERGE_API_TOKEN\" -o ORDER_FILE.gz ; then
    mkdir -p \"$PROJECT_DIR/orderfiles\"
    gunzip -c ORDER_FILE.gz > $PROJECT_DIR/orderfiles/orderfile.txt
else
    echo \"cURL request failed. Creating an empty file.\"
    mkdir -p \"$PROJECT_DIR/orderfiles\" 
    touch \"$PROJECT_DIR/orderfiles/orderfile.txt\"
fi;"
              phase.output_paths = ['$(PROJECT_DIR)/orderfiles/orderfile.txt']
            else
                Logger.info "  'Download Order Files' already exists"
            end
            # Make sure it is the first build phase
            target.build_phases.move(phase, 0)

            target.build_configurations.each do |config|
              config.build_settings[ORDER_FILE] = '$(PROJECT_DIR)/orderfiles/orderfile.txt'
            end
          end
        end
      end
    end
  end
end
