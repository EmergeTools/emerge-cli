module EmergeCLI
  module Commands
    module Upload
      module ClientLibraries
        class Paparazzi
          def initialize(project_root)
            @project_root = project_root
          end

          def image_files
            # TODO: support "paparazzi.snapshot.dir" dynamic config
            Dir.glob(File.join(@project_root, '**/src/test/snapshots/images/**/*.png'))
          end

          def parse_file_info(image_path)
            file_name = image_path.split('src/test/snapshots/images/').last
            test_class_name = File.basename(File.dirname(image_path))

            {
              file_name:,
              group_name: test_class_name, # TODO: add support for nicer group names
              variant_name: File.basename(file_name, '.*')
            }
          end
        end
      end
    end
  end
end
