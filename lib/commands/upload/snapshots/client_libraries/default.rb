module EmergeCLI
  module Commands
    module Upload
      module ClientLibraries
        class Default
          def initialize(image_paths)
            @image_paths = image_paths
          end

          def image_files
            @image_paths.flat_map { |path| Dir.glob("#{path}/**/*.png") }
          end

          def parse_file_info(image_path)
            file_name = File.basename(image_path)
            {
              file_name:,
              group_name: File.basename(image_path, '.*'),
              variant_name: nil
            }
          end
        end
      end
    end
  end
end
