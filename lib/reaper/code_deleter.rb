require 'xcodeproj'

module EmergeCLI
  module Reaper
    class CodeDeleter
      def initialize(project_root:, platform:)
        @project_root = File.expand_path(project_root)
        @platform = platform
        Logger.debug "Initialized CodeDeleter with project root: #{@project_root}, platform: #{@platform}"
      end

      def delete_types(types)
        Logger.debug "Project root: #{@project_root}"

        types.each do |class_info|
          Logger.info "Deleting #{class_info['class_name']}"

          type_name = class_info['class_name']
          # Remove first module prefix for Swift types if present
          type_name = type_name.split('.')[1..].join('.') if @platform == 'ios' && type_name.include?('.')

          paths = class_info['paths']
          if paths.nil? || paths.empty?
            Logger.info "No paths provided for #{type_name}, scanning project..."
            paths = find_type_in_project(type_name)
            if paths.empty?
              Logger.warn "Could not find any files containing #{type_name}"
              next
            end
            Logger.info "Found #{type_name} in: #{paths.join(', ')}"
          end

          paths.each do |path|
            path = path.sub(%r{^/}, '')
            full_path = File.join(@project_root, path)
            Logger.debug "Processing path: #{path}"
            Logger.debug "Resolved full path: #{full_path}"
            delete_type_from_file(full_path, type_name)
          end
        end
      end

      private

      def delete_type_from_file(full_path, type_name)
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
          parser = AstParser.new(language)
          modified_contents = parser.delete_type(
            file_contents: original_contents,
            type_name: type_name
          )

          if modified_contents.nil?
            File.delete(full_path)
            delete_type_from_xcode_project(full_path) if language == 'swift'
            Logger.info "Deleted file #{full_path} as it only contained #{type_name}"
          elsif modified_contents != original_contents
            File.write(full_path, modified_contents)
            Logger.info "Successfully deleted #{type_name} from #{full_path}"
          else
            Logger.warn "No changes made to #{full_path} for #{type_name}"
          end
        rescue StandardError => e
          Logger.error "Failed to delete #{type_name} from #{full_path}: #{e.message}"
          Logger.error e.backtrace.join("\n")
        end
      end

      def delete_type_from_xcode_project(file_path)
        xcodeproj_path = Dir.glob(File.join(@project_root, '**/*.xcodeproj')).first
        if xcodeproj_path.nil?
          Logger.warn "No Xcode project found in #{@project_root}"
          return
        end

        begin
          project = Xcodeproj::Project.open(xcodeproj_path)
          relative_path = Pathname.new(file_path).relative_path_from(Pathname.new(@project_root)).to_s

          file_ref = project.files.find { |f| f.real_path.to_s.end_with?(relative_path) }
          if file_ref
            file_ref.remove_from_project
            project.save
            Logger.info "Removed #{relative_path} from Xcode project"
          else
            Logger.warn "Could not find #{relative_path} in Xcode project"
          end
        rescue StandardError => e
          Logger.error "Failed to update Xcode project: #{e.message}"
          Logger.error e.backtrace.join("\n")
        end
      end

      def find_type_in_project(type_name)
        matching_paths = []
        source_patterns = case @platform&.downcase
                         when 'ios'
                           { 'swift' => '**/*.swift' }
                         when 'android'
                           {
                             'kotlin' => '**/*.kt',
                             'java' => '**/*.java'
                           }
                         else
                           raise "Unsupported platform: #{@platform}"
                         end

        source_patterns.each do |language, pattern|
          Dir.glob(File.join(@project_root, pattern)).each do |file_path|
            begin
              Logger.debug "Scanning #{file_path} for #{type_name}"
              contents = File.read(file_path)
              parser = AstParser.new(language)
              usages = parser.find_usages(file_contents: contents, type_name: type_name)

              if usages.any?
                Logger.debug "✅ Found #{type_name} in #{file_path}"
                relative_path = Pathname.new(file_path).relative_path_from(Pathname.new(@project_root)).to_s
                matching_paths << relative_path
              end
            rescue StandardError => e
              Logger.warn "Error scanning #{file_path}: #{e.message}"
            end
          end
        end

        matching_paths
      end
    end
  end
end
