module Bindgen
  # Stores a analyzed call to a method.
  class Call
    # Base-class for `Result` and `Argument`.
    abstract class Expression
      # The data this expression originated in.
      getter type : Parser::Type

      # Pass in as reference?
      getter reference : Bool

      # Pointer depth, *without* the reference "pointer"
      getter pointer : Int32

      # Type to use for passing
      getter type_name : String

      # Is this expression nil-able?  A type is only nil-able if the wrapped
      # type is an object-type (`Reference` in Crystal), and the C++-world
      # accepts this pointer being `nullptr`.
      getter? nilable : Bool

      def initialize(@type, @reference, @pointer, @type_name, @nilable)
      end
    end

    # Call result type configuration.
    class Result < Expression
    # Conversion template (`Util.template`) to get the data out of the method,
      # ready to be returned back.
      getter conversion : String?

      def initialize(@type, @type_name, @reference, @pointer, @conversion, @nilable = false)
      end

      # Converts the result into an argument of *name*.
      def to_argument(name : String, default = nil) : Argument
        call = name
        templ = @conversion # Conversion template
        call = Util.template(templ, name) if templ

        Argument.new(
          type: @type,
          type_name: @type_name,
          name: name,
          call: call,
          reference: @reference,
          pointer: @pointer,
          nilable: @nilable,
          default_value: default,
        )
      end
    end

    # A result specifying a `Proc`.
    class ProcResult < Result
      # The wrapped *method*
      getter method : Parser::Method

      def initialize(@method, @type_name, @reference = false, @pointer = 0, @conversion = nil)
        @nilable = false
        @type = @method.return_type
      end

      # Converts the result into an argument of *name*.
      def to_argument(name : String, block = false) : Argument
        call = name
        templ = @conversion # Conversion template
        call = Util.template(templ, name) if templ

        ProcArgument.new(
          method: @method,
          block: block,
          type_name: @type_name,
          name: name,
          call: call,
          reference: @reference,
          pointer: @pointer,
        )
      end
    end

    # A `Call` argument.
    class Argument < Expression
      # The variable name.
      getter name : String

      # How to use the argument variable.
      getter call : String

      # Default value for this argument.
      getter default_value : Parser::Argument::DefaultValueTypes?

      def initialize(@type, @type_name, @name, @call, @reference = false, @pointer = 0, @default_value = nil, @nilable = false)
      end
    end

    # A `Proc` argument.  May be a block.
    class ProcArgument < Argument
      # Is this a block argument?
      getter? block : Bool

      # The wrapped *method*
      getter method : Parser::Method

      def initialize(@method, @type_name, @name, @call, @reference, @pointer, @block = false)
        @default_value = nil
        @nilable = false
        @type = @method.return_type
      end
    end

    # Origin method
    getter origin : Parser::Method

    # Full name of the method call, e.g. `new Foo` or `_self_->doIt`.
    getter name : String

    # Arguments
    getter arguments : Array(Argument)

    # Return type
    getter result : Result

    def initialize(@origin, @name, @result, @arguments)
    end
  end
end
