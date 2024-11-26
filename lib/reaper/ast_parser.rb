require 'tree_sitter'

module Emerge
  module Reaper
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

        case language
        when 'swift'
          @parser.language = TreeSitter.lang('swift')
        when 'kotlin'
          @parser.language = TreeSitter.lang('kotlin')
        when 'java'
          @parser.language = TreeSitter.lang('java')
        else
          raise "Unsupported language: #{language}"
        end
      end

      def delete_type(file_contents:, type_name:)
        @current_file_contents = file_contents
        tree = @parser.parse_string(nil, file_contents)
        cursor = TreeSitter::TreeCursor.new(tree.root_node)
        nodes_to_process = [cursor.current_node]
        lines_to_remove = []

        while (node = nodes_to_process.shift)
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

      def find_usages(file_contents:, type_name:)
        @current_file_contents = file_contents
        tree = @parser.parse_string(nil, file_contents)
        cursor = TreeSitter::TreeCursor.new(tree.root_node)
        usages = []
        nodes_to_process = [cursor.current_node]

        while (node = nodes_to_process.shift)
          identifier_type = identifier_node_types.include?(node.type)
          declaration_type = declaration_node_types.include?(node.parent&.type)

          if declaration_type
            if fully_qualified_type_name(node) == type_name
              usages << { line: node.start_point.row, usage_type: 'declaration' }
            end
          elsif identifier_type
            usages << { line: node.start_point.row, usage_type: 'identifier' } if node_text(node) == type_name
          end

          node.each { |child| nodes_to_process.push(child) }
        end

        usages
      end

      private

      def remove_node(node, lines_to_remove)
        start_position = node.start_point.row
        end_position = node.end_point.row
        lines_to_remove << { start: start_position, end: end_position }

        # Remove comments before class declaration
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
    end
  end
end
