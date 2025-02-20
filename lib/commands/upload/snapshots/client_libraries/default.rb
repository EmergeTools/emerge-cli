module EmergeCLI
  module Commands
    module Upload
      module ClientLibraries
        class Default
          def initialize(image_paths, group_delimiter)
            @image_paths = image_paths
            @group_delimiter = group_delimiter
          end

          def image_files
            @image_paths.flat_map { |path| Dir.glob("#{path}/**/*.png") }
          end

          def parse_file_info(image_path)
            file_name = File.basename(image_path)
            file_name_without_extension = File.basename(file_name, '.*')
            parts = file_name_without_extension.split(@group_delimiter)
            group_name = parts.first
            variant_name = parts[1..].join(@group_delimiter)
            {
              file_name:,
              group_name:,
              variant_name:
            }
          end
        end
      end
    end
  end
end
