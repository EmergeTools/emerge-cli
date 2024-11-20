module EmergeCLI
  module Commands
    module Upload
      module ClientLibraries
        class Roborazzi
          def initialize(project_root)
            @project_root = project_root
          end

          def image_files
            Dir.glob(File.join(@project_root, '**/build/outputs/roborazzi/**/*.png'))
          end

          def parse_file_info(image_path)
            file_name = image_path.split('build/outputs/roborazzi/').last
            base_name = File.basename(file_name, '.png')
            parts = base_name.split('.')

            # Get the last two parts regardless of whether there's a package name in the file name
            # For "com.example.MyTest.testName" -> ["MyTest", "testName"]
            # For "MyTest.testName" -> ["MyTest", "testName"]
            relevant_parts = parts.last(2)

            {
              file_name:,
              group_name: relevant_parts[0],
              variant_name: relevant_parts[1]
            }
          end
        end
      end
    end
  end
end
