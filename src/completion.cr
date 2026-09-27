require "./docopt"

# Shared machinery for the shell completion generators.
#
# CommandParams is the parameter tree (options, arguments and
# subcommands at every command level) extracted from a docopt usage
# pattern, and Completion is the base class the bash, fish and zsh
# generators build on, so the doc-to-tree half exists exactly once.
#
# The tree building is a port of Infinidat's infi.docopt_completion;
# see LICENSE.completion.

module Docopt
  extend self

  # Contains command options, arguments and subcommands.
  #
  # Options are optional arguments like "-v", "-h", etc.
  #
  # Arguments are required arguments like file paths, etc.
  #
  # Subcommands are optional keywords, like the "status" in "git status".
  # Subcommands have their own CommandParams instance, so the "status" in "git status" can
  # have its own options, arguments and subcommands.
  #
  # This way, we can describe commands like "git remote add origin --fetch" with all the different
  # options at each level.
  class CommandParams
    property arguments : Array(String) = [] of String
    # Option names as the completion generators list them, with a
    # trailing "=" when the option takes a value ("-v", "--speed=").
    property options : Array(String) = [] of String
    # The same options with their short and long forms kept paired,
    # deduplicated, so each generator emits one rule per option.
    property option_specs : Array(OptionSpec) = [] of OptionSpec
    property subcommands : Hash(String, CommandParams) = Hash(String, CommandParams).new

    def get_subcommand(subcommand : String) : CommandParams
      subcommands[subcommand] ||= CommandParams.new
    end

    def add_option_spec(spec : OptionSpec) : Nil
      return if option_specs.any? { |existing| existing.short == spec.short && existing.long == spec.long }
      option_specs << spec
    end

    def repr(indent : Int32 = 0) : String
      s = " " * indent + "cmds:\n"
      subcommands.each do |cmd, subcommand|
        s += " " * (indent + 4) + "#{cmd}:\n#{subcommand.repr(indent + 5 + cmd.size)}\n"
      end
      s += " " * indent + "args: #{arguments}\n"
      s += " " * indent + "opts: #{options}\n"
      s
    end
  end

  # A declared option: its short and long forms (either may be
  # missing) and whether it takes a value.
  struct OptionSpec
    getter short : String?
    getter long : String?
    getter? takes_value : Bool

    def initialize(@short : String?, @long : String?, @takes_value : Bool)
    end

    # The name docopt reports for the option, long form preferred.
    def name : String?
      long || short
    end

    # The option's names as words in completion lists, with a
    # trailing "=" for options that take a value.
    def words : Array(String)
      words = [] of String
      if short_name = @short
        words << (@takes_value ? "#{short_name}=" : short_name)
      end
      if long_name = @long
        words << (@takes_value ? "#{long_name}=" : long_name)
      end
      words
    end
  end

  # Base class for the per-shell completion script generators. It owns
  # the doc, its usage section and the custom completions, and turns
  # the doc into the CommandParams tree every shell consumes.
  abstract class Completion
    @doc : String
    @usage : String
    @custom_completions : Hash(String, String)

    # A nil doc builds a generator that will only ever be handed a
    # prebuilt tree (see the tree-based completion entry points).
    def initialize(doc : String?, @custom_completions = {} of String => String)
      @doc = ""
      @usage = ""
      if doc
        sections = Docopt.parse_section("usage:", doc)
        if sections.empty?
          raise DocoptLanguageError.new("\"usage:\" (case-insensitive) not found.")
        end
        @doc = doc
        @usage = sections[0]
      end
    end

    # Where the generated script is conventionally installed.
    abstract def completion_path : String

    # The parameter tree for the doc, plus a hash of option name
    # (short and long, without any trailing "=") to its description.
    def parse_params : Tuple(CommandParams, Hash(String, String))
      options = Docopt.parse_defaults(@doc)
      option_help = build_option_help(options)
      pattern = Docopt.parse_pattern(
        Docopt.formal_usage(@usage), options)
      expand_options_shortcut(pattern, options)
      param_tree = CommandParams.new
      build_command_tree(pattern, param_tree)
      {param_tree, option_help}
    end

    # Description for an option as it appears in the tree (with a
    # trailing "=" when it takes a value), falling back to the option
    # name itself.
    def description_for(option : String, option_help : Hash(String, String)) : String
      option_help[option.chomp("=")]? || option
    end

    # The custom completion declared for an option, keyed by its
    # reported name or by its short form.
    def custom_for(spec : OptionSpec) : String?
      if name = spec.name
        if custom = @custom_completions[name]?
          return custom
        end
      end
      if short_name = spec.short
        @custom_completions[short_name]?
      end
    end

    # Shell-safe identifier from a command or subcommand name:
    # invalid characters become underscores.
    def sanitize_name(name : String) : String
      name.gsub(/[^a-zA-Z0-9_]/, "_")
    end

    # Recursively fill in a command tree according to a docopt-parsed
    # pattern object.
    #
    # ameba:disable Metrics/CyclomaticComplexity
    def build_command_tree(pattern : Docopt::Pattern, cmd_params : CommandParams) : CommandParams
      case pattern
      when Docopt::Either, Docopt::Optional, Docopt::OneOrMore
        if children = pattern.children.as?(Array(Docopt::Pattern))
          children.each do |child|
            build_command_tree(child, cmd_params)
          end
        end
      when Docopt::Required
        if children = pattern.children.as?(Array(Docopt::Pattern))
          children.each do |child|
            cmd_params = build_command_tree(child, cmd_params)
          end
        end
      when Docopt::Option
        takes_value = pattern.argcount > 0
        cmd_params.add_option_spec(OptionSpec.new(pattern.short, pattern.long, takes_value))
        suffix = takes_value ? "=" : ""
        if short_name = pattern.short
          cmd_params.options << "#{short_name}#{suffix}"
        end
        if long_name = pattern.long
          cmd_params.options << "#{long_name}#{suffix}"
        end
      when Docopt::Command
        cmd_params = cmd_params.get_subcommand(pattern.name.to_s)
      when Docopt::Argument
        cmd_params.arguments << pattern.name.to_s
      end
      cmd_params
    end

    # option -> help text, keyed by every declared name. The [default: ...]
    # annotation is stripped: it is noise in a completion description.
    private def build_option_help(options : Array(Option)) : Hash(String, String)
      option_help = Hash(String, String).new
      options.each do |option|
        description = option.description.gsub(/\s*\[default:\s*[^\]]*\]/i, "").strip
        if short_name = option.short
          option_help[short_name] = description
        end
        if long_name = option.long
          option_help[long_name] = description
        end
      end
      option_help
    end

    # [options] shortcuts contribute nothing until their children are
    # set to the options the usage pattern does not mention itself,
    # like Docopt.parse does for matching.
    private def expand_options_shortcut(pattern : Pattern, options : Array(Option)) : Nil
      pattern_options = pattern.flat Option
      pattern.flat(AnyOptions).each do |shortcut|
        branch = shortcut.as(BranchPattern)
        branch.children = (options - pattern_options).uniq.map { |option| option.as(Pattern) }
      end
    end
  end

  # Reads a doc's CommandParams tree without generating any script:
  # the shared entry point for tree consumers, like Dispatch's
  # whole-registry completions.
  class DocTree < Completion
    def completion_path : String
      ""
    end

    def self.read(doc : String) : Tuple(CommandParams, Hash(String, String))
      new(doc).parse_params
    end
  end
end
