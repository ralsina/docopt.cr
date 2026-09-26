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

    # The value every declared option parses to when absent from argv:
    # its [default: ...] value (an array for repeated options, since
    # the pattern is fixed), false for flags, nil for options without
    # a default. This is what a result hash falls back to, so layered
    # configuration can use it as the lowest-precedence tier without
    # re-parsing the doc.
    def defaults : Result
      result = Result.new
      options.each do |option|
        if name = option.name
          result[name] = option.value
        end
      end
      result
    end

    # A copy of this compiled pattern with declared option defaults
    # neutralized: argument options with a [default: ...] value parse
    # to nil when absent, while flags (false), counters (0) and
    # repeated options ([]) keep their usual absent values. Matching
    # argv against it is equivalent to matching the same doc with the
    # [default: ...] annotations stripped, so callers can tell "given
    # on the command line" apart from "fell back to the default" —
    # `defaults` supplies the declared values for the fallback tier.
    #
    # Like the original (see `to_crystal`), equal leaves are the same
    # object in the pattern tree and the options list, and neither the
    # original nor the copy is mutated by matching.
    def without_defaults : Compiled
      copies = {} of UInt64 => Pattern
      new_options = options.map do |option|
        Compiled.neutralized_copy(option, copies).as(Option)
      end
      new_pattern = Compiled.neutralized_copy(pattern, copies)
      Compiled.new(doc, usage, new_options, new_pattern)
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
        io << "    [" << options.map { |option| locals[option.object_id] }.join(", ") << "] of Docopt::Option,\n"
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

    # Deep-copy a pattern for `without_defaults`, sharing one copy of
    # each distinct node (keyed by object id) between every place it
    # appears, like `fix_identities` and `to_crystal` do.
    protected def self.neutralized_copy(node : Pattern, copies : Hash(UInt64, Pattern)) : Pattern
      if existing = copies[node.object_id]?
        return existing
      end

      copy =
        case node
        when Option
          value = node.value
          if node.argcount > 0
            value = nil if value.is_a?(String)
            value = [] of String if value.is_a?(Array(String))
          end
          Option.new(node.short, node.long, node.argcount, value, node.description)
        when Command
          Command.new(node.name, node.value)
        when Argument
          Argument.new(node.name, node.value)
        when BranchPattern
          node.class.new(copy_children(node, copies))
        else
          raise DocoptLanguageError.new "Cannot copy #{node.class}"
        end
      copies[node.object_id] = copy
      copy
    end

    protected def self.copy_children(node : BranchPattern, copies : Hash(UInt64, Pattern)) : Array(Pattern)
      children = node.children.as(Array(Pattern))
      children.map { |child| neutralized_copy(child, copies) }
    end
  end
end
