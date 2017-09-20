module Bindgen
  module Graph
    # Builds a graph out of `Parser::*` structures.  Can be used to build a
    # whole namespace out of a `Parser::Document`, or just for smaller things.
    #
    # The resulting graph mirrors the structure of the target language.
    class Builder
      def initialize(@db : TypeDatabase)
      end

      # Copies *document* into the *ns*.
      def build_document(document : Parser::Document, ns : Namespace) : Namespace
        # Add classes first, so that enums can end up in their target class.
        document.classes.each do |_, klass|
          target_name = @db[klass.name].crystal_type || klass.name
          build_class(klass, target_name, ns)
        end

        # Add enums second
        document.enums.each do |_, enumeration|
          target_name = @db[enumeration.name].crystal_type || enumeration.name
          build_enum(enumeration, target_name, ns)
        end

        ns # Done!
      end

      # Copies *klass* at path *name* into the *root*.
      def build_class(klass : Parser::Class, name : String, root : Graph::Container) : Graph::Class
        parent, local_name = parent_and_local_name(root, name)

        # Create the class itself
        graph_class = Graph::Class.new(
          parent: parent,
          name: local_name,
          origin: klass,
        )

        # Add all (in theory) wrappable methods
        klass.wrap_methods.each do |method|
          build_method(method, graph_class)
        end

        # Store graph node in the type database
        @db.get_or_add(klass.name).graph_node = graph_class
        graph_class
      end

      # Copies *enumeration* at path *name* into the *root*.
      def build_enum(enumeration : Parser::Enum, name : String, root : Graph::Container) : Graph::Enum
        parent, local_name = parent_and_local_name(root, name)

        graph_enum = Graph::Enum.new(
          parent: parent,
          name: local_name,
          origin: enumeration,
        )

        # Store graph node in the type database
        @db.get_or_add(enumeration.name).graph_node = graph_enum
        graph_enum
      end

      # Copies *method* into *parent*.
      def build_method(method : Parser::Method, parent : Graph::Node?) : Graph::Method
        Graph::Method.new(
          origin: method,
          name: method.name,
          parent: parent,
        )
      end

      # Splits the qualified *path*, and returns the parent of the target
      # and the name of the *path* local to the parent.
      def parent_and_local_name(root : Graph::Container, path : String)
        path_parts = path_name(path)
        parent = get_or_create_path_parent(root, path_parts)
        local_name = path_parts.last

        { parent, local_name }
      end

      # Gets the parent of *path*, starting at *root*.  Makes sure it is a
      # `Graph::Container`.  Also see `#get_or_create_path`
      def get_or_create_path_parent(root : Graph::Container, path : Enumerable(String)) : Graph::Container
        parent = get_or_create_path(root, path[0..-2])

        unless parent.is_a?(Graph::Container)
          raise "Expected a container (module or class) at #{path.join "::"}, but got a #{parent.class} instead"
        end

        parent
      end

      # Iterates over the *path*, descending from *root* onwards.  If a part of
      # the path does not exist yet, it'll be created as `Namespace`.
      def get_or_create_path(root : Graph::Container, path : Enumerable(String)) : Graph::Node
        path.reduce(root) do |ctr, name|
          unless ctr.is_a?(Graph::Container)
            raise "Path #{path.inspect} is illegal, as #{name.inspect} is not a container"
          end

          parent = ctr.nodes.find(&.name.== name)
          if parent.nil? # Create a new module if it doesn't exist.
            parent = Graph::Namespace.new(name: name, parent: ctr)
          end

          parent
        end
      end

      # Splits up the path in *crystal_name*.
      def path_name(crystal_name : String)
        # Nothing special here, just to have this logic in one place only.
        crystal_name.split("::")
      end
    end
  end
end
