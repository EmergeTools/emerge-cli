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

          type_name = parse_type_name(class_info['class_name'])
          Logger.debug "Parsed type name: #{type_name}"

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
            Logger.debug "Processing path: #{path}"
            @profiler.measure('delete_type_from_file') do
              delete_type_from_file(path, type_name)
            end
          end

          # Second pass: Delete remaining usages (unless skipped)
          if @skip_delete_usages
            Logger.info 'Skipping delete usages'
          else
            identifier_usages = found_usages.select do |usage|
              usage[:usages].any? { |u| u[:usage_type] == 'identifier' }
            end
            identifier_usage_paths = identifier_usages.map { |usage| usage[:path] }.uniq
            if identifier_usage_paths.empty?
              Logger.info 'No identifier usages found, skipping delete usages'
            else
              identifier_usage_paths.each do |path|
                Logger.debug "Processing usages in path: #{path}"
                @profiler.measure('delete_usages_from_file') do
                  delete_usages_from_file(path, type_name)
                end
              end
            end
          end
        end
      end

      private

      def parse_type_name(type_name)
        # Remove first module prefix for Swift types if present
        if @platform == 'ios' && type_name.include?('.')
          type_name.split('.')[1..].join('.')
        # For Android, strip package name and just use the class name
        elsif @platform == 'android' && type_name.include?('.')
          # rubocop:disable Layout/LineLength
          # Handle cases like "com.emergetools.hackernews.data.remote.ItemResponse $NullResponse (HackerNewsBaseClient.kt)"
          # rubocop:enable Layout/LineLength
          type_name = if type_name.include?('$') && type_name.match(/\((.*?)\)/)
                        base_name = type_name.split('$').first.strip
                        nested_class = type_name.split('$')[1].split('(').first.strip
                        "#{base_name}.#{nested_class}"
                      else
                        type_name
                      end
          type_name.split('.').last(2).join('.')
        else
          type_name
        end
      end

      def delete_type_from_file(path, type_name)
        full_path = resolve_file_path(path)
        return unless full_path

        Logger.debug "Processing file: #{full_path}"
        begin
          original_contents = @profiler.measure('read_file') { File.read(full_path) }
          parser = make_parser_for_file(full_path)
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
            if parser.language == 'swift'
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

      def resolve_file_path(path)
        # If path starts with /, treat it as relative to project root
        if path.start_with?('/')
          path = path[1..] # Remove leading slash
          full_path = File.join(@project_root, path)
          return full_path if File.exist?(full_path)
        end

        # Try direct path first
        full_path = File.join(@project_root, path)
        return full_path if File.exist?(full_path)

        # If not found, search recursively
        Logger.debug "File not found at #{full_path}, searching in project..."
        matching_files = Dir.glob(File.join(@project_root, '**', path))
                            .reject { |p| p.include?('/build/') }

        if matching_files.empty?
          Logger.warn "Could not find #{path} in project"
          return nil
        elsif matching_files.length > 1
          Logger.warn "Found multiple matches for #{path}: #{matching_files.join(', ')}"
          Logger.warn "Using first match: #{matching_files.first}"
        end

        matching_files.first
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
          Dir.glob(File.join(@project_root, pattern)).reject { |path| path.include?('/build/') }.each do |file_path|
            Logger.debug "Scanning #{file_path} for #{type_name}"
            contents = File.read(file_path)
            parser = make_parser_for_file(file_path)
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

      def delete_usages_from_file(full_path, type_name)
        return unless File.exist?(full_path)

        begin
          original_contents = File.read(full_path)
          parser = make_parser_for_file(full_path)
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

      def make_parser_for_file(file_path)
        language = case File.extname(file_path)
                   when '.swift' then 'swift'
                   when '.kt' then 'kotlin'
                   when '.java' then 'java'
                   else
                     raise "Unsupported file type for #{file_path}"
                   end
        AstParser.new(language)
      end
    end
  end
end
