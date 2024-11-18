module EmergeCLI
  module Commands
    module Upload
      module ClientLibraries
        class SwiftSnapshotTesting
          def initialize(project_root)
            @project_root = project_root
          end

          def image_files
            Dir.glob(File.join(@project_root, '**/__Snapshots__/**/*.png'))
          end

          def parse_file_info(image_path)
            file_name = image_path.split('__Snapshots__/').last
            test_class_name = File.basename(File.dirname(image_path))

            {
              file_name:,
              group_name: test_class_name.sub(/Tests$/, ''),
              variant_name: File.basename(file_name, '.*')
            }
          end
        end
      end
    end
  end
end
