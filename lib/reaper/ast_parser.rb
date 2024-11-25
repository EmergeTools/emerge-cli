require 'tree_sitter'

module Emerge
  module Reaper
    class AstParser
      DECLARATION_NODE_TYPES = {
        'swift' => ['class_declaration', 'protocol_declaration'],
        'kotlin' => ['class_declaration', 'protocol_declaration', 'interface_declaration'],
        'java' => ['class_declaration', 'protocol_declaration', 'interface_declaration']
      }.freeze

      IDENTIFIER_NODE_TYPES = {
        'swift' => ['simple_identifier', 'qualified_name', 'identifier', 'type_identifier'],
        'kotlin' => ['simple_identifier', 'qualified_name', 'identifier', 'type_identifier'],
        'java' => ['simple_identifier', 'qualified_name', 'identifier', 'type_identifier']
      }.freeze

      COMMENT_AND_IMPORT_NODE_TYPES = {
        'swift' => ['comment', 'import_declaration'],
        'kotlin' => ['comment', 'import_header'],
        'java' => ['comment', 'import_declaration']
      }.freeze

      attr_reader :parser, :language

      def initialize(language)
        @parser = TreeSitter::Parser.new
        @language = language

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
        tree = @parser.parse_string(file_contents)
        cursor = tree.root_node.walk
        nodes_to_process = [cursor.current_node]
        lines_to_remove = []

        modified_source = file_contents

        while (node = nodes_to_process.shift)
          if declaration_node_types.include?(node.type)
            type_identifier_node = find_type_identifier(node)
            if type_identifier_node && fully_qualified_type_name(type_identifier_node) == type_name
              remove_node(node, lines_to_remove)
            end
          end

          if extension?(node)
            user_type_nodes = node.children.select { |n| n.type == 'user_type' }
            if user_type_nodes.length >= 1 && fully_qualified_type_name(user_type_nodes[0]) == type_name
              remove_node(node, lines_to_remove)
            end
          end

          node.named_children.each { |child| nodes_to_process.push(child) }
        end

        lines = file_contents.split("\n")
        lines_to_remove.each do |range|
          (range[:start]..range[:end]).each { |i| lines[i] = nil }

          # Remove extra newline after class declaration
          if range[:end] + 1 < lines.length &&
             lines[range[:end] + 1] &&
             lines[range[:end] + 1].match?(/^\s*$/)
            lines[range[:end] + 1] = nil
          end
        end

        modified_source = lines.compact.join("\n")
        new_tree = @parser.parse_string(modified_source)

        return nil if only_comments_and_imports?(new_tree.root_node.walk)
        modified_source
      end

      def find_usages(file_contents:, type_name:)
        tree = @parser.parse_string(file_contents)
        cursor = tree.root_node.walk
        usages = []
        nodes_to_process = [cursor.current_node]

        while (node = nodes_to_process.shift)
          identifier_type = identifier_node_types.include?(node.type)
          declaration_type = declaration_node_types.include?(node.parent&.type.to_s)

          if declaration_type
            if fully_qualified_type_name(node) == type_name
              usages << { line: node.start_position.row, usage_type: 'declaration' }
            end
          elsif identifier_type
            if node.text == type_name
              usages << { line: node.start_position.row, usage_type: 'identifier' }
            end
          end

          node.children.each { |child| nodes_to_process.push(child) }
        end

        usages
      end

      private

      def remove_node(node, lines_to_remove)
        start_position = node.start_position.row
        end_position = node.end_position.row
        lines_to_remove << { start: start_position, end: end_position }

        # Remove comments before class declaration
        predecessor = node.previous_named_sibling
        if predecessor && predecessor.type == 'comment'
          lines_to_remove << { start: predecessor.start_position.row, end: predecessor.end_position.row }
        end
      end

      def extension?(node)
        if node.type == 'class_declaration'
          extension_node = node.children.select { |c| c.type == 'extension' }
          return true if extension_node.length == 1
        end
        false
      end

      def only_comments_and_imports?(root)
        children = root.current_node.children
        types = comment_and_import_types
        children.all? { |child| types.include?(child.type) }
      end

      def fully_qualified_type_name(node)
        class_name = node.text
        current_node = node
        parent = find_parent_type_declaration(current_node)

        while parent
          type_identifier = find_type_identifier(parent)
          user_type = find_user_type(parent)

          if type_identifier && type_identifier != current_node
            class_name = "#{type_identifier.text}.#{class_name}"
            current_node = type_identifier
          elsif user_type && user_type != current_node
            class_name = "#{user_type.text}.#{class_name}"
            current_node = user_type
          end

          parent = find_parent_type_declaration(parent)
        end

        class_name
      end

      def find_parent_type_declaration(node)
        parent = node.parent
        while parent
          return parent if declaration_node_types.include?(parent.type)
          parent = parent.parent
        end
        nil
      end

      def find_type_identifier(node)
        identifier_types = identifier_node_types
        node.named_children.find { |child| identifier_types.include?(child.type) }
      end

      def find_user_type(node)
        node.named_children.find { |child| child.type == 'user_type' }
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
    end
  end
end
