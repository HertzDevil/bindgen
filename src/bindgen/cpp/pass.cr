module Bindgen
  module Cpp
    # Methods for passing data from and to C++.
    #
    # This is a helper struct: Cheap to create and to pass around.
    struct Pass
      include TypeHelper

      def initialize(@db : TypeDatabase)
      end

      # Turns the list of arguments into a list of `Call::Argument`s.
      def arguments_to_cpp(list : Enumerable(Parser::Argument))
        list.map_with_index do |arg, idx|
          to_cpp(arg).to_argument(Argument.name(arg, idx))
        end
      end

      # ditto
      def arguments_from_cpp(list : Enumerable(Parser::Argument))
        list.map_with_index do |arg, idx|
          passthrough_to_crystal(arg).to_argument(Argument.name(arg, idx))
        end
      end

      # ditto
      def through_arguments(list : Enumerable(Parser::Argument))
        list.map_with_index do |arg, idx|
          through(arg).to_argument(Argument.name(arg, idx))
        end
      end

      # Returns the type name of *proc_type*.
      def crystal_proc_name(proc_type : Parser::Type) : String
        typer = Typename.new
        inner_args = proc_type.template.not_nil!.arguments

        # Arguments go C++ -> Crystal, but the result goes Crystal -> C++!
        proc_types = inner_args[1..-1].map{|t| to_crystal(t)}
        proc_types.unshift to_cpp(inner_args.first)

        proc_args = typer.full(proc_types).join(", ")
        "CrystalProc<#{proc_args}>"
      end

      # Computes a result for passing *type* from Crystal to C++.
      #
      # The primary job of this method is to figure out how to pass something of
      # *type* over to C++.  It doesn't matter if this is a result from a method
      # or an argument for this.  It also signals how a value of this type shall
      # be handled by the receiver, e.g., if conversions apply (Which?).
      #
      # The method responsible for the opposite direction is `#pass_to_crystal`.
      #
      # Pass rules:
      # 1. The type is a value-type and passed by-value
      #   a. The type is copied? Then pass by-value.
      #   b. Else, pass by-reference.
      # 2. The type is passed by-reference
      #   a. Pass by-reference
      # 2. The type is passed by-pointer
      #   a. Pass by-pointer
      def to_cpp(type : Parser::Type) : Call::Result
        is_copied = is_type_copied?(type)
        is_ref = type.reference?
        is_val = type.pointer < 1
        ptr = type_pointer_depth(type)

        type_name = type.base_name
        type_name = crystal_proc_name(type) if type.kind.function?

        # If the method expects a value, but we don't copy its structure, we pass
        # a reference to it instead.
        if is_val && !is_copied
          is_ref = true
          ptr = 0
        end

        if rules = @db[type]?
          template = rules.to_cpp
          type_name = rules.cpp_type || type_name
          is_ref, ptr = reconfigure_pass_type(rules.pass_by, is_ref, ptr)
        end

        Call::Result.new(
          type: type,
          type_name: type_name,
          reference: is_ref,
          pointer: ptr,
          conversion: template,
        )
      end

      # Computes a result for passing *type* from C++ to Crystal.
      # Also see `#pass_to_cpp` for the reverse direction.
      # See `#passthrough_to_crystal` to call Crystal from C++.
      #
      # Set *is_constructor* to `true` if this is a return-result of a method
      # and this method is a constructor.
      #
      # Pass rules:
      # 1. If *is_constructor* and the type is copied
      #   a. Then pass by-value.  (See `MethodName#generate` too)
      # 2. If pass by-reference
      #   a. Invoke the types copy-constructor and pass by-pointer.
      # 3. If pass by-value but the type is not copied
      #   a. Invoke the types copy-constructor and pass by-pointer.
      # 4. In all other cases
      #   a. Pass by-reference or by-pointer as defined by *type*.
      def to_crystal(type : Parser::Type, is_constructor = false) : Call::Result
        is_copied = is_type_copied?(type)
        is_ref = type.reference?
        ptr = type_pointer_depth(type)
        is_val = type.pointer < 1
        type_name = type.base_name
        generate_template = false

        # TODO: Check for copy-constructor.
        if (is_constructor || is_val) && is_copied
          is_ref = false
          ptr = 0
        elsif is_ref || (is_val && !is_copied)
          is_ref = false
          ptr = 1

          generate_template = !is_copied
        end

        if rules = @db[type]?
          # Support `from_cpp`.
          # generate_template = false unless rules.pass_by.original?
          template = rules.from_cpp
          type_name = rules.cpp_type || type_name
          is_ref, ptr = reconfigure_pass_type(rules.pass_by, is_ref, ptr)
        end

        if generate_template && template.nil?
          template = "new (UseGC) #{type_name} (%)"
        end

        Call::Result.new(
          type: type,
          type_name: type_name,
          reference: is_ref,
          pointer: ptr,
          conversion: template,
        )
      end

      # Computes a result which is directly usable from C++ code, without
      # changes, and passes it through to crystal using conversion.
      #
      # The pass rules are similar to `#to_crystal`.  The primary
      # difference is that this version has no special handling of constructors.
      #
      # There is a second major difference:  This method always signals the C++
      # type to the outside, as received by C++ (Thus even ignoring
      # `rules.cpp_type`!).  It still follows the passing rules towards Crystal.
      def passthrough_to_crystal(type : Parser::Type)
        is_copied = is_type_copied?(type)
        is_ref = type.reference?
        is_val = type.pointer < 1
        ptr = type_pointer_depth(type)
        type_name = type.base_name
        type_name = crystal_proc_name(type) if type.kind.function?

        conversion_type_name = type_name
        generate_template = false

        # TODO: Check for copy-constructor.
        if !is_copied && (is_ref || is_val)
          # Don't change the external type (is_ref, ptr)!
          generate_template = true
        end

        if rules = @db[type]?
          # Support `from_cpp`.
          template = rules.from_cpp

          # We accept a C++ type here: The original one!  Don't let the user
          # overwrite this, as it would result in a compilation error anyway.
          conversion_type_name = rules.cpp_type || conversion_type_name
        end

        if generate_template && template.nil?
          template = "new (UseGC) #{conversion_type_name} (%)"
        end

        Call::Result.new(
          type: type,
          type_name: type_name,
          reference: is_ref,
          pointer: ptr,
          conversion: template,
        )
      end

      # Passes the *type* through without changes.
      def through(type : Parser::Type)
        type_name = type.base_name
        type_name = crystal_proc_name(type) if type.kind.function?

        Call::Result.new(
          type: type,
          type_name: type_name,
          reference: type.reference?,
          pointer: type_pointer_depth(type),
          conversion: nil,
        )
      end
    end
  end
end
