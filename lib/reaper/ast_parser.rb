require 'tree_sitter'

module EmergeCLI
  module Reaper
    # Parses the AST of a given file using Tree Sitter and allows us to find usages or delete types.
    # This does have a lot of limitations since it only looks at a single file at a time,
    # but can get us most of the way there.
    class AstParser
      DECLARATION_NODE_TYPES = {
        'swift' => %i[class_declaration protocol_declaration],
        'kotlin' => %i[class_declaration protocol_declaration interface_declaration],
        'java' => %i[class_declaration protocol_declaration interface_declaration]
      }.freeze

      IDENTIFIER_NODE_TYPES = {
        'swift' => %i[simple_identifier qualified_name identifier type_identifier],
        'kotlin' => %i[simple_identifier qualified_name identifier type_identifier],
        'java' => %i[simple_identifier qualified_name identifier type_identifier]
      }.freeze

      COMMENT_AND_IMPORT_NODE_TYPES = {
        'swift' => %i[comment import_declaration],
        'kotlin' => %i[comment import_header],
        'java' => %i[comment import_declaration]
      }.freeze

      attr_reader :parser, :language

      def initialize(language)
        @parser = TreeSitter::Parser.new
        @language = language
        @current_file_contents = nil

        platform = case RUBY_PLATFORM
                   when /darwin/
                     'darwin'
                   when /linux/
                     'linux'
                   else
                     raise "Unsupported platform: #{RUBY_PLATFORM}"
                   end

        arch = case RUBY_PLATFORM
               when /x86_64|amd64/
                 'x86_64'
               when /arm64|aarch64/
                 'arm64'
               else
                 raise "Unsupported architecture: #{RUBY_PLATFORM}"
               end

        extension = platform == 'darwin' ? 'dylib' : 'so'
        parser_file = "libtree-sitter-#{language}-#{platform}-#{arch}.#{extension}"
        parser_path = File.join('parsers', parser_file)

        case language
        when 'swift'
          @parser.language = TreeSitter::Language.load('swift', parser_path)
        when 'kotlin'
          @parser.language = TreeSitter::Language.load('kotlin', parser_path)
        when 'java'
          @parser.language = TreeSitter::Language.load('java', parser_path)
        else
          raise "Unsupported language: #{language}"
        end
      end

      # Deletes a type from the given file contents.
      # Returns the modified file contents if successful, otherwise nil.
      # TODO(telkins): Look into the tree-sitter query API to see if it simplifies this.
      def delete_type(file_contents:, type_name:)
        @current_file_contents = file_contents
        tree = @parser.parse_string(nil, file_contents)
        cursor = TreeSitter::TreeCursor.new(tree.root_node)
        nodes_to_process = [cursor.current_node]
        lines_to_remove = []

        while (node = nodes_to_process.shift)
          Logger.debug "Processing node: #{node.type} #{node_text(node)}"
          if declaration_node_types.include?(node.type)
            type_identifier_node = find_type_identifier(node)
            if type_identifier_node && fully_qualified_type_name(type_identifier_node) == type_name
              remove_node(node, lines_to_remove)
            end
          end

          if extension?(node)
            user_type_nodes = node.select { |n| n.type == :user_type }
            if user_type_nodes.length >= 1 && fully_qualified_type_name(user_type_nodes[0]) == type_name
              remove_node(node, lines_to_remove)
            end
          end

          node.each_named { |child| nodes_to_process.push(child) }
        end

        lines = file_contents.split("\n")
        lines_to_remove.each do |range|
          Logger.debug "Removing lines #{range[:start]} to #{range[:end]}"
          (range[:start]..range[:end]).each { |i| lines[i] = nil }

          # Remove extra newline after class declaration, but only if it's blank
          if range[:end] + 1 < lines.length && !lines[range[:end] + 1].nil? && lines[range[:end] + 1].match?(/^\s*$/)
            lines[range[:end] + 1] = nil
          end
        end

        modified_source = lines.compact.join("\n")
        new_tree = @parser.parse_string(nil, modified_source)

        return nil if only_comments_and_imports?(TreeSitter::TreeCursor.new(new_tree.root_node))
        modified_source
      end

      # Finds all usages of a given type in a file.
      # TODO(telkins): Look into the tree-sitter query API to see if it simplifies this.
      def find_usages(file_contents:, type_name:)
        @current_file_contents = file_contents
        tree = @parser.parse_string(nil, file_contents)
        cursor = TreeSitter::TreeCursor.new(tree.root_node)
        usages = []
        nodes_to_process = [cursor.current_node]

        while (node = nodes_to_process.shift)
          identifier_type = identifier_node_types.include?(node.type)
          declaration_type = if node == tree.root_node
                               false
                             else
                               declaration_node_types.include?(node.parent&.type)
                             end
          if declaration_type && fully_qualified_type_name(node) == type_name
            usages << { line: node.start_point.row, usage_type: 'declaration' }
          elsif identifier_type && node_text(node) == type_name
            usages << { line: node.start_point.row, usage_type: 'identifier' }
          end

          node.each { |child| nodes_to_process.push(child) }
        end

        usages
      end

      def delete_usage(file_contents:, type_name:)
        @current_file_contents = file_contents
        tree = @parser.parse_string(nil, file_contents)
        cursor = TreeSitter::TreeCursor.new(tree.root_node)
        nodes_to_process = [cursor.current_node]
        nodes_to_remove = []

        Logger.debug "Starting to scan for usages of #{type_name}"

        while (node = nodes_to_process.shift)
          identifier_type = identifier_node_types.include?(node.type)
          if identifier_type && node_text(node) == type_name
            Logger.debug "Found usage of #{type_name} in node type: #{node.type}"
            # Find the smallest removable expression containing this type
            removable_node = find_removable_parent(node)
            if removable_node
              Logger.debug "Will remove parent node of type: #{removable_node.type}"
              Logger.debug "Node text to remove: #{node_text(removable_node)}"
              nodes_to_remove << removable_node
            else
              Logger.debug "No suitable parent node found for removal"
            end
          end

          node.each { |child| nodes_to_process.push(child) }
        end

        return file_contents if nodes_to_remove.empty?

        Logger.debug "Found #{nodes_to_remove.length} nodes to remove"

        # Sort nodes by their position in reverse order to avoid offset issues
        nodes_to_remove.sort_by! { |n| -n.start_byte }

        # Remove each node by replacing its text with empty string
        modified_contents = file_contents.dup
        nodes_to_remove.each do |node|
          start_byte = node.start_byte
          end_byte = node.end_byte
          text_to_remove = modified_contents[start_byte...end_byte]
          Logger.debug "Removing text: #{text_to_remove}"
          modified_contents[start_byte...end_byte] = ''
        end

        # Clean up any empty lines or extra whitespace
        Logger.debug "Cleaning up whitespace and formatting"
        modified_contents.gsub!(/\n\s*\n\s*\n/, "\n\n") # Collapse multiple empty lines
        modified_contents.gsub!(/,\s*,/, ',') # Clean up consecutive commas
        modified_contents.gsub!(/\(\s*\)/, '()') # Clean up empty parentheses

        modified_contents
      end

      private

      def remove_node(node, lines_to_remove)
        Logger.debug "Removing node: #{node.type}"
        start_position = node.start_point.row
        end_position = node.end_point.row
        lines_to_remove << { start: start_position, end: end_position }

        # Remove comments preceding the class declaration
        predecessor = node.prev_named_sibling
        return unless predecessor && predecessor.type == :comment
        lines_to_remove << { start: predecessor.start_point.row, end: predecessor.end_point.row }
      end

      def extension?(node)
        if node.type == :class_declaration
          !node.find { |n| n.type == :extension }.nil?
        else
          false
        end
      end

      def only_comments_and_imports?(root)
        types = comment_and_import_types
        root.current_node.all? do |child|
          types.include?(child.type)
        end
      end

      # Reaper expects a fully qualified type name, so we need to extract it from the AST.
      # E.g. `MyModule.MyClass`
      def fully_qualified_type_name(node)
        class_name = node_text(node)
        current_node = node
        parent = find_parent_type_declaration(current_node)

        while parent
          type_identifier = find_type_identifier(parent)
          user_type = find_user_type(parent)

          if type_identifier && type_identifier != current_node
            class_name = "#{node_text(type_identifier)}.#{class_name}"
            current_node = type_identifier
          elsif user_type && user_type != current_node
            class_name = "#{node_text(user_type)}.#{class_name}"
            current_node = user_type
          end

          parent = find_parent_type_declaration(parent)
        end

        class_name
      end

      def find_parent_type_declaration(node)
        return nil unless node&.parent

        current = node.parent
        while current && !current.null?
          return current if current.type && declaration_node_types.include?(current.type)
          break unless current.parent && !current.parent.null?
          current = current.parent
        end
        nil
      end

      def find_type_identifier(node)
        node.find { |n| identifier_node_types.include?(n.type) }
      end

      def find_user_type(node)
        node.find { |n| n.type == :user_type }
      end

      def declaration_node_types
        DECLARATION_NODE_TYPES[language]
      end

      def identifier_node_types
        IDENTIFIER_NODE_TYPES[language]
      end

      def comment_and_import_types
        COMMENT_AND_IMPORT_NODE_TYPES[language]
      end

      def node_text(node)
        return '' unless @current_file_contents
        start_byte = node.start_byte
        end_byte = node.end_byte
        @current_file_contents[start_byte...end_byte]
      end

      def find_removable_parent(node)
        current = node
        Logger.debug "Finding removable parent for node type: #{node.type}"

        while current && !current.null?
          Logger.debug "Checking parent node type: #{current.type}"
          case current.type
          when :variable_declaration, # var foo: DeletedType
               :parameter, # func example(param: DeletedType)
               :type_annotation, # : DeletedType
               :argument, # functionCall(param: DeletedType)
               :import_declaration, # import DeletedType
               :navigation_expression # NetworkDebugger.printStats
            if current.type == :navigation_expression
              # If this navigation expression is part of a call, remove the entire call
              parent_call = current.parent
              if parent_call && parent_call.type == :call_expression
                Logger.debug "Found call expression containing navigation expression"
                return parent_call
              end
            end
            Logger.debug "Found removable parent node of type: #{current.type}"
            return current
          when :class_declaration, :function_declaration, :method_declaration
            Logger.debug "Reached structural element, stopping at: #{current.type}"
            break
          end
          current = current.parent
        end

        Logger.debug "No better parent found, returning original node"
        node
      end
    end
  end
end
