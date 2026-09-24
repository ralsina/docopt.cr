module Docopt
  # A parsed usage text: the cleaned documentation, the usage section,
  # the option defaults and the fixed pattern tree. Produced by
  # `Docopt.parse` at runtime or by `Docopt.compile` at compile time,
  # and consumed by `Docopt.match`.
  class Compiled
    getter doc : String
    getter usage : String
    getter options : Array(Option)
    getter pattern : Pattern

    def initialize(@doc : String, @usage : String, @options : Array(Option), @pattern : Pattern)
    end

    # Crystal source for an expression that rebuilds this object.
    #
    # After `Pattern#fix_identities` equal leaves are the same object
    # and the matcher relies on that, so every distinct leaf becomes a
    # local variable that the tree and the options list refer to. The
    # locals live inside a proc so they do not leak into the caller.
    def to_crystal : String
      String.build do |io|
        locals = {} of UInt64 => String
        io << "(-> {\n"
        (pattern.flat + options.map(&.as(Pattern))).each do |leaf|
          next if locals.has_key?(leaf.object_id)
          name = "docopt_leaf_#{locals.size}"
          locals[leaf.object_id] = name
          io << "  " << name << " = "
          Compiled.leaf_to_crystal(leaf, io)
          io << "\n"
        end
        io << "  Docopt::Compiled.new(\n"
        io << "    " << doc.inspect << ",\n"
        io << "    " << usage.inspect << ",\n"
        io << "    [" << options.map { |o| locals[o.object_id] }.join(", ") << "] of Docopt::Option,\n"
        io << "    "
        Compiled.pattern_to_crystal(pattern, locals, io)
        io << "\n  )\n}).call"
      end
    end

    protected def self.pattern_to_crystal(node : Pattern, locals : Hash(UInt64, String), io : IO) : Nil
      if node.is_a?(LeafPattern)
        io << locals[node.object_id]
        return
      end
      io << "Docopt::" << node.class.name.split("::").last << ".new(["
      children = node.children.as(Array(Pattern))
      children.each_with_index do |child, index|
        io << ", " if index > 0
        pattern_to_crystal(child, locals, io)
      end
      io << "] of Docopt::Pattern)"
    end

    protected def self.leaf_to_crystal(leaf : Pattern, io : IO) : Nil
      case leaf
      when Option
        io << "Docopt::Option.new(" << leaf.short.inspect << ", " << leaf.long.inspect << ", " << leaf.argcount << ", "
        value_to_crystal(leaf.value, io)
        io << ", " << leaf.description.inspect << ")"
      when Command
        io << "Docopt::Command.new(" << leaf.name.inspect << ", "
        value_to_crystal(leaf.value, io)
        io << ")"
      when Argument
        io << "Docopt::Argument.new(" << leaf.name.inspect << ", "
        value_to_crystal(leaf.value, io)
        io << ")"
      else
        raise DocoptLanguageError.new "Cannot serialize #{leaf.class}"
      end
    end

    protected def self.value_to_crystal(value, io : IO) : Nil
      case value
      when Array(String)
        if value.empty?
          io << "[] of String"
        else
          io << value.inspect
        end
      else
        io << value.inspect
      end
    end
  end
end
