require 'xcodeproj'

module EmergeCLI
  module Reaper
    class CodeDeleter
      def initialize(project_root:, platform:, profiler:, skip_delete_usages: false)
        @project_root = File.expand_path(project_root)
        @platform = platform
        @profiler = profiler
        @skip_delete_usages = skip_delete_usages
        Logger.debug "Initialized CodeDeleter with project root: #{@project_root}, platform: #{@platform}"
      end

      def delete_types(types)
        Logger.debug "Project root: #{@project_root}"

        types.each do |class_info|
          Logger.info "Deleting #{class_info['class_name']}"

          type_name = class_info['class_name']
          # Remove first module prefix for Swift types if present
          type_name = type_name.split('.')[1..].join('.') if @platform == 'ios' && type_name.include?('.')

          # Remove line number from path if present
          paths = class_info['paths']&.map { |path| path.sub(/:\d+$/, '') }
          found_usages = @profiler.measure('find_type_in_project') do
            find_type_in_project(type_name)
          end

          if paths.nil? || paths.empty?
            Logger.info "No paths provided for #{type_name}, using found usages instead..."
            paths = found_usages
                    .select { |usage| usage[:usages].any? { |u| u[:usage_type] == 'declaration' } }
                    .map { |usage| usage[:path] }
            if paths.empty?
              Logger.warn "Could not find any files containing #{type_name}"
              next
            end
            Logger.info "Found #{type_name} in: #{paths.join(', ')}"
          end

          # First pass: Delete declarations
          paths.each do |path|
            path = path.sub(%r{^/}, '')
            full_path = File.join(@project_root, path)
            Logger.debug "Processing path: #{path}"
            Logger.debug "Resolved full path: #{full_path}"
            @profiler.measure('delete_type_from_file') do
              delete_type_from_file(full_path, type_name)
            end
          end

          # Second pass: Delete remaining usages (unless skipped)
          next if @skip_delete_usages
          # Re-scan for usages since line numbers may have changed
          identifier_usages = found_usages.select do |usage|
            usage[:usages].any? do |u|
              u[:usage_type] == 'identifier'
            end
          end
          identifier_usage_paths = identifier_usages.map { |usage| usage[:path] }.uniq
          identifier_usage_paths.each do |path|
            full_path = File.join(@project_root, path)
            Logger.debug "Processing usages in path: #{path}"
            @profiler.measure('delete_usages_from_file') do
              delete_usages_from_file(full_path, type_name)
            end
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
          original_contents = @profiler.measure('read_file') { File.read(full_path) }
          parser = AstParser.new(language)
          modified_contents = @profiler.measure('parse_and_delete_type') do
            parser.delete_type(
              file_contents: original_contents,
              type_name: type_name
            )
          end

          if modified_contents.nil?
            @profiler.measure('delete_file') do
              File.delete(full_path)
            end
            if language == 'swift'
              @profiler.measure('delete_type_from_xcode_project') do
                delete_type_from_xcode_project(full_path)
              end
            end
            Logger.info "Deleted file #{full_path} as it only contained #{type_name}"
          elsif modified_contents != original_contents
            @profiler.measure('write_file') do
              File.write(full_path, modified_contents)
            end
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
        found_usages = []
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
          # Exclude files in build directories, e.g. for Android
          Dir.glob(File.join(@project_root, pattern)).reject { |path| path.include?('/build/') }.each do |file_path|
            Logger.debug "Scanning #{file_path} for #{type_name}"
            contents = File.read(file_path)
            parser = AstParser.new(language)
            usages = parser.find_usages(file_contents: contents, type_name: type_name)

            if usages.any?
              Logger.debug "✅ Found #{type_name} in #{file_path}"
              relative_path = Pathname.new(file_path).relative_path_from(Pathname.new(@project_root)).to_s
              found_usages << {
                path: relative_path,
                usages: usages,
                language: language
              }
            end
          rescue StandardError => e
            Logger.warn "Error scanning #{file_path}: #{e.message}"
          end
        end

        found_usages
      end

      # New method to handle deletion of type usages
      def delete_usages_from_file(full_path, type_name)
        return unless File.exist?(full_path)

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

          modified_contents = parser.delete_usage(
            file_contents: original_contents,
            type_name: type_name
          )

          if modified_contents != original_contents
            File.write(full_path, modified_contents)
            Logger.info "Successfully removed usages of #{type_name} from #{full_path}"
          end
        rescue StandardError => e
          Logger.error "Failed to delete usages of #{type_name} from #{full_path}: #{e.message}"
          Logger.error e.backtrace.join("\n")
        end
      end
    end
  end
end
