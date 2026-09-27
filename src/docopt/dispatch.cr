require "../docopt"

# Subcommand-oriented dispatch on top of docopt: git-style tools where
# each subcommand carries its own complete docopt help text.
#
# Users subclass Docopt::Dispatch::Command, set the command name and
# its doc, implement run, and register; Docopt::Dispatch.main parses
# argv, dispatches to the command and returns its exit code.
#
# This layer grew out of the polydocopt shard, which now re-exports it
# for compatibility.

module Docopt
  module Dispatch
    extend self

    # A command. Subclass this to define a new command.
    #
    # Requirements:
    # - set @@name to the command name
    # - set @@doc to a docopt document describing the command
    #   (its first paragraph is shown as the command summary)
    # - implement run, returning the process exit code
    #
    # The name "help" is reserved.

    abstract struct Command
      property options : Hash(String, (String | Int32 | Bool | Array(String))?)
      class_property name : String = "command"
      class_property doc : String = ""

      def initialize(@options)
      end

      def self.register
        has_usage = @@doc.split("\n").any?(&.downcase.lstrip.starts_with?("usage:"))
        raise ArgumentError.new("#{@@name} has no 'Usage:' section in its documentation") unless has_usage
        raise ArgumentError.new("A command named '#{@@name}' is already registered") if COMMANDS.has_key?(@@name)
        COMMANDS[@@name] = self
      end

      # The command's doc, parsed once per command no matter how many
      # times dispatch runs.
      def self.compiled : Docopt::Compiled
        if pattern = COMPILED[@@name]?
          pattern
        else
          COMPILED[@@name] = Docopt.parse(@@doc)
        end
      end

      abstract def run : Int32
    end

    # Command class registry
    COMMANDS = {} of String => Command.class

    # Parsed docs for the registered commands, keyed by command name
    COMPILED = {} of String => Docopt::Compiled

    # Main entry point. Call this with the program name and ARGV.
    # Returns the exit code of the executed command, so a typical
    # program ends with: `exit(Docopt::Dispatch.main("prog", ARGV))`
    def self.main(progname : String, args : Array(String), stdout : IO = STDOUT, stderr : IO = STDERR) : Int32
      return print_top_level_help(progname, stdout) if args.empty? || args[0] == "-h" || args[0] == "--help"
      return help_command(progname, args, stdout, stderr) if args[0] == "help"

      command_name = args[0]
      command = COMMANDS.fetch(command_name, nil)
      unless command
        stderr.puts not_a_command_message(progname, command_name)
        return 1
      end

      return print_command_help(command, stdout) if wants_help?(args)

      begin
        options = Docopt.match(command.compiled, args, help: false, exit: false)
      rescue error : Docopt::DocoptLanguageError
        stderr.puts "Invalid documentation for command '#{command_name}': #{error.message}"
        return 1
      rescue error : Docopt::DocoptExit
        message = error.message
        stderr.puts message if message && !message.empty?
        stderr.puts command.compiled.usage
        stderr.puts
        stderr.puts "See '#{progname} help #{command_name}' for more information."
        return 1
      end

      command.new(options).run
    end

    private def self.wants_help?(args : Array(String)) : Bool
      # Only words before a "--" separator can be a help request; a
      # literal "-h" after it is a positional argument.
      limit = args.index("--") || args.size
      args.skip(1).first(limit - 1).any? { |arg| arg == "-h" || arg == "--help" }
    end

    private def self.help_command(progname : String, args : Array(String), stdout : IO, stderr : IO) : Int32
      begin
        options = Docopt.docopt(top_level_doc(progname), args, help: false, exit: false)
      rescue Docopt::DocoptExit
        stderr.puts Docopt::DocoptExit.usage
        return 1
      end

      requested = options["COMMAND"]?
      return print_top_level_help(progname, stdout) unless requested.is_a?(String)

      command = COMMANDS.fetch(requested, nil)
      unless command
        stderr.puts not_a_command_message(progname, requested)
        return 1
      end

      print_command_help(command, stdout)
    end

    private def self.print_top_level_help(progname : String, stdout : IO) : Int32
      stdout.puts top_level_doc(progname)
      0
    end

    private def self.print_command_help(command : Command.class, stdout : IO) : Int32
      stdout.puts command.doc.strip
      0
    end

    private def self.top_level_doc(progname : String) : String
      lines = [
        "Help about the #{progname} command.",
        "",
        "Usage:",
        "  #{progname} help [COMMAND]",
        "",
        "Commands:",
      ]

      width = {COMMANDS.keys.max_of(&.size) || 0, 10}.max + 2
      COMMANDS.each do |command_name, command|
        lines << "  #{command_name.ljust(width)}#{summary(command.doc)}".rstrip
      end

      lines.join("\n")
    end

    private def self.summary(doc : String) : String
      doc.split("\n")
        .take_while { |line| !line.downcase.lstrip.starts_with?("usage:") }
        .map(&.strip)
        .reject(&.empty?)
        .first? || ""
    end

    private def self.not_a_command_message(progname : String, attempted : String) : String
      message = "#{progname}: '#{attempted}' is not a #{progname} command. See '#{progname} help'."
      suggestions = suggestions_for(attempted)
      if suggestions.size > 0
        heading = suggestions.size == 1 ? "The most similar command is" : "The most similar commands are"
        message += "\n\n#{heading}"
        suggestions.each do |candidate|
          message += "\n\t#{candidate}"
        end
      end
      message
    end

    # Candidates close to *attempted*, closest first: every candidate
    # within a case-insensitive Levenshtein distance of
    # `max(attempted.size // 3, 2)`, at most four, ties broken
    # alphabetically. Defaults to the registered command names; the
    # implementation lives in the core (Docopt.suggestions_for) and
    # powers its "did you mean" error messages too.
    def self.suggestions_for(attempted : String, candidates : Array(String) = COMMANDS.keys) : Array(String)
      Docopt.suggestions_for(attempted, candidates)
    end

    # One completion tree covering every registered command: the root
    # completes the command names (plus help), and each command's own
    # options, arguments and subcommands come from its doc. Custom
    # completions follow the generators' convention: the command path
    # joined with "_" ("say_hello"), or an option name.
    def self.completion_params : Tuple(CommandParams, Hash(String, String))
      root = CommandParams.new
      option_help = Hash(String, String).new
      COMMANDS.each do |name, command|
        doc_tree, doc_help = DocTree.read(command.doc)
        root.subcommands[name] = doc_tree.subcommands.fetch(name, doc_tree)
        option_help.merge!(doc_help)
      end
      root.subcommands["help"] = CommandParams.new
      {root, option_help}
    end

    # A bash completion script for every registered command.
    def self.bash_completion(cmd : String, custom_completions = {} of String => String) : String
      param_tree, option_help = completion_params
      Docopt.bash_completion(cmd, param_tree, option_help, custom_completions)
    end

    # A fish completion script for every registered command.
    def self.fish_completion(cmd : String, custom_completions = {} of String => String) : String
      param_tree, option_help = completion_params
      Docopt.fish_completion(cmd, param_tree, option_help, custom_completions)
    end

    # A zsh completion script for every registered command.
    def self.zsh_completion(cmd : String, custom_completions = {} of String => String) : String
      param_tree, option_help = completion_params
      Docopt.zsh_completion(cmd, param_tree, option_help, custom_completions)
    end

    # Case-insensitive Levenshtein edit distance; see
    # Docopt.levenshtein_distance in the core.
    def self.levenshtein_distance(left : String, right : String) : Int32
      Docopt.levenshtein_distance(left, right)
    end
  end
end
