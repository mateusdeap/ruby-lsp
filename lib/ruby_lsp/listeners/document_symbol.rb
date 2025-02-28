# typed: strict
# frozen_string_literal: true

module RubyLsp
  module Listeners
    class DocumentSymbol
      extend T::Sig
      extend T::Generic
      include Requests::Support::Common

      ATTR_ACCESSORS = T.let([:attr_reader, :attr_writer, :attr_accessor].freeze, T::Array[Symbol])

      sig do
        params(
          stack: Response::DocumentSymbolStack,
          dispatcher: Prism::Dispatcher,
        ).void
      end
      def initialize(stack, dispatcher)
        @stack = stack

        dispatcher.register(
          self,
          :on_class_node_enter,
          :on_class_node_leave,
          :on_call_node_enter,
          :on_constant_path_write_node_enter,
          :on_constant_write_node_enter,
          :on_def_node_enter,
          :on_def_node_leave,
          :on_module_node_enter,
          :on_module_node_leave,
          :on_instance_variable_write_node_enter,
          :on_class_variable_write_node_enter,
          :on_singleton_class_node_enter,
          :on_singleton_class_node_leave,
        )
      end

      sig { params(node: Prism::ClassNode).void }
      def on_class_node_enter(node)
        @stack << create_document_symbol(
          name: node.constant_path.location.slice,
          kind: Constant::SymbolKind::CLASS,
          range_location: node.location,
          selection_range_location: node.constant_path.location,
        )
      end

      sig { params(node: Prism::ClassNode).void }
      def on_class_node_leave(node)
        @stack.pop
      end

      sig { params(node: Prism::SingletonClassNode).void }
      def on_singleton_class_node_enter(node)
        expression = node.expression

        @stack << create_document_symbol(
          name: "<< #{expression.slice}",
          kind: Constant::SymbolKind::NAMESPACE,
          range_location: node.location,
          selection_range_location: expression.location,
        )
      end

      sig { params(node: Prism::SingletonClassNode).void }
      def on_singleton_class_node_leave(node)
        @stack.pop
      end

      sig { params(node: Prism::CallNode).void }
      def on_call_node_enter(node)
        return unless ATTR_ACCESSORS.include?(node.name) && node.receiver.nil?

        arguments = node.arguments
        return unless arguments

        arguments.arguments.each do |argument|
          next unless argument.is_a?(Prism::SymbolNode)

          name = argument.value
          next unless name

          create_document_symbol(
            name: name,
            kind: Constant::SymbolKind::FIELD,
            range_location: argument.location,
            selection_range_location: T.must(argument.value_loc),
          )
        end
      end

      sig { params(node: Prism::ConstantPathWriteNode).void }
      def on_constant_path_write_node_enter(node)
        create_document_symbol(
          name: node.target.location.slice,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.target.location,
        )
      end

      sig { params(node: Prism::ConstantWriteNode).void }
      def on_constant_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::CONSTANT,
          range_location: node.location,
          selection_range_location: node.name_loc,
        )
      end

      sig { params(node: Prism::DefNode).void }
      def on_def_node_leave(node)
        @stack.pop
      end

      sig { params(node: Prism::ModuleNode).void }
      def on_module_node_enter(node)
        @stack << create_document_symbol(
          name: node.constant_path.location.slice,
          kind: Constant::SymbolKind::MODULE,
          range_location: node.location,
          selection_range_location: node.constant_path.location,
        )
      end

      sig { params(node: Prism::DefNode).void }
      def on_def_node_enter(node)
        receiver = node.receiver
        previous_symbol = @stack.last

        if receiver.is_a?(Prism::SelfNode)
          name = "self.#{node.name}"
          kind = Constant::SymbolKind::FUNCTION
        elsif previous_symbol.is_a?(Interface::DocumentSymbol) && previous_symbol.name.start_with?("<<")
          name = node.name.to_s
          kind = Constant::SymbolKind::FUNCTION
        else
          name = node.name.to_s
          kind = name == "initialize" ? Constant::SymbolKind::CONSTRUCTOR : Constant::SymbolKind::METHOD
        end

        symbol = create_document_symbol(
          name: name,
          kind: kind,
          range_location: node.location,
          selection_range_location: node.name_loc,
        )

        @stack << symbol
      end

      sig { params(node: Prism::ModuleNode).void }
      def on_module_node_leave(node)
        @stack.pop
      end

      sig { params(node: Prism::InstanceVariableWriteNode).void }
      def on_instance_variable_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::VARIABLE,
          range_location: node.name_loc,
          selection_range_location: node.name_loc,
        )
      end

      sig { params(node: Prism::ClassVariableWriteNode).void }
      def on_class_variable_write_node_enter(node)
        create_document_symbol(
          name: node.name.to_s,
          kind: Constant::SymbolKind::VARIABLE,
          range_location: node.name_loc,
          selection_range_location: node.name_loc,
        )
      end

      private

      sig do
        params(
          name: String,
          kind: Integer,
          range_location: Prism::Location,
          selection_range_location: Prism::Location,
        ).returns(Interface::DocumentSymbol)
      end
      def create_document_symbol(name:, kind:, range_location:, selection_range_location:)
        symbol = Interface::DocumentSymbol.new(
          name: name,
          kind: kind,
          range: range_from_location(range_location),
          selection_range: range_from_location(selection_range_location),
          children: [],
        )

        @stack.last.children << symbol

        symbol
      end
    end
  end
end
