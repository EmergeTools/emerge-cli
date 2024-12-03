module EmergeCLI
  module Reaper
    class CodeDeleter
      def initialize(project_root: Dir.pwd)
        @project_root = File.expand_path(project_root)
        Logger.debug "Initialized CodeDeleter with project root: #{@project_root}"
      end

      def delete(classes)
        Logger.debug "Project root: #{@project_root}"

        classes.each do |class_info|
          Logger.info "Deleting #{class_info['class_name']}"
          type_name = class_info['class_name']
          paths = class_info['paths']

          paths.each do |path|
            path = path.sub(/^\//, '')
            full_path = File.join(@project_root, path)
            Logger.debug "Processing path: #{path}"
            Logger.debug "Resolved full path: #{full_path}"
            delete_from_file(full_path, type_name)
          end
        end
      end

      private

      def delete_from_file(full_path, type_name)
        if !File.exist?(full_path)
          Logger.warn "File does not exist: #{full_path}"
          return
        end

        language = case File.extname(full_path)
                  when '.swift' then 'swift'
                  when '.kt' then 'kotlin'
                  when '.java' then 'java'
                  else
                    Logger.warn "Unsupported file type for #{full_path}"
                    return
                  end

        begin
          original_contents = File.read(full_path)
          binding.pry
          parser = AstParser.new(language)
          modified_contents = parser.delete_type(
            file_contents: original_contents,
            type_name: type_name
          )

          if modified_contents && modified_contents != original_contents
            File.write(full_path, modified_contents)
            Logger.info "Successfully deleted #{type_name} from #{full_path}"
          else
            Logger.warn "No changes made to #{full_path} for #{type_name}"
          end
        rescue => e
          Logger.error "Failed to delete #{type_name} from #{full_path}: #{e.message}"
          Logger.error e.backtrace.join("\n")
        end
      end
    end
  end
end
