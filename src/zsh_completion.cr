require "./docopt"

# ZSH shell completion generation for docopt
#
# This module provides ZSH shell completion functionality by leveraging
# the same parsing infrastructure as the bash completion.

module Docopt
  extend self

  class ZshCompletion
    @doc : String
    @usage : String
    @custom_completions : Hash(String, String)

    def initialize(@doc, @custom_completions = {} of String => String)
      @usage = Docopt.parse_section("usage:", @doc)[0]
    end

    def get_completion_path : String
      "/usr/share/zsh/site-functions"
    end

    def get_completion_filepath(cmd : String) : String
      "#{get_completion_path}/_#{cmd}"
    end

    def sanitize_name(name : String) : String
      # ZSH function names need to be valid shell identifiers
      name.gsub(/[^a-zA-Z0-9_]/, "_")
    end

    def create_option_args(options : Array(String), option_help : Hash(String, String)) : Array(String)
      return [] of String if options.empty?

      args = [] of String

      options.each do |option|
        description = option_help[option]? || option
        if option.starts_with?("--")
          # Long option
          arg_name = option[2..]
          option_name = option.chomp("=")

          if option.ends_with?("=") && @custom_completions.has_key?(option_name)
            # Option takes an argument with custom completion
            custom_completion = @custom_completions[option_name]
            args << "'--#{arg_name}[#{description}]:{$(#{custom_completion})}'"
          elsif option.ends_with?("=")
            # Option takes an argument without custom completion
            args << "'--#{arg_name[0..-2]}[#{description}]:'"
          else
            # Boolean option
            args << "'--#{arg_name}[#{description}]'"
          end
        elsif option.starts_with?("-") && option.size > 1
          # Short option
          arg_name = option[1]
          option_name = option.chomp("=")

          if option.ends_with?("=") && @custom_completions.has_key?(option_name)
            # Option takes an argument with custom completion
            custom_completion = @custom_completions[option_name]
            args << "'-#{arg_name}[#{description}]:{$(#{custom_completion})}'"
          elsif option.ends_with?("=")
            # Option takes an argument without custom completion
            args << "'-#{arg_name}[#{description}]:'"
          else
            # Boolean option
            args << "'-#{arg_name}[#{description}]'"
          end
        end
      end

      args
    end

    def create_command_args(subcommands : Hash(String, CommandParams)) : Array(String)
      return [] of String if subcommands.empty?

      args = subcommands.map do |subcommand_name, subcommand_tree|
        "'#{subcommand_name}:#{subcommand_name}'"
      end

      args
    end

    def create_argument_completions(arguments : Array(String), custom_name : String) : Array(String)
      return [] of String if arguments.empty?

      # Check for custom completion first
      if @custom_completions.has_key?(custom_name)
        custom_completion = @custom_completions[custom_name]
        return ["{$(#{custom_completion})}"]
      end

      # Default to file completion for arguments
      ["_files"]
    end

    def create_function_body(cmd_name : String, param_tree : CommandParams, option_help : Hash(String, String), command_parts : Array(String), indent : Int32 = 0) : String
      lines = [] of String
      indent_str = "  " * indent

      # Handle state machine for subcommands
      unless param_tree.subcommands.empty?
        lines << "#{indent_str}local -a commands"
        command_args = create_command_args(param_tree.subcommands)
        lines << "#{indent_str}commands=(#{command_args.join(" ")})"

        lines << "#{indent_str}_describe 'command' commands"
        lines << ""
      end

      # Handle options
      unless param_tree.options.empty?
        option_args = create_option_args(param_tree.options, option_help)
        lines << "#{indent_str}_arguments -s -S #{option_args.join(" ")}" unless option_args.empty?
      end

      # Handle arguments with proper custom completion names
      unless param_tree.arguments.empty?
        custom_name = command_parts.join("_")
        argument_completions = create_argument_completions(param_tree.arguments, custom_name)
        argument_completions.each do |completion|
          lines << "#{indent_str}#{completion}"
        end
      end

      lines.join("\n")
    end

    def create_completion_function(cmd_name : String, param_tree : CommandParams, option_help : Hash(String, String), function_name : String? = nil, command_parts : Array(String) = [] of String) : String
      function_name ||= "_#{sanitize_name(cmd_name)}"
      current_command_parts = command_parts.empty? ? [cmd_name] : command_parts

      # Main function header
      header = <<-HEADER
#{function_name}() {
  local context state line
  typeset -A opt_args

HEADER

      # Create state machine for subcommands
      state_machine = create_state_machine(cmd_name, param_tree, option_help, function_name)

      # Main function body
      body = create_function_body(cmd_name, param_tree, option_help, current_command_parts, 1)

      # Generate subcommand functions
      subcommand_functions = ""
      param_tree.subcommands.each do |subcommand_name, subcommand_tree|
        sub_function_name = "#{function_name}_#{subcommand_name}"
        new_command_parts = current_command_parts + [subcommand_name]
        subcommand_functions += "\n" + create_completion_function(cmd_name, subcommand_tree, option_help, sub_function_name, new_command_parts)
      end

      # Footer
      footer = "\n}"

      "#{header}#{state_machine}#{body}#{subcommand_functions}#{footer}"
    end

    def create_state_machine(cmd_name : String, param_tree : CommandParams, option_help : Hash(String, String), function_name : String) : String
      return "" if param_tree.subcommands.empty?

      lines = [] of String

      # Create case statement for subcommands
      lines << "  case $state in"
      lines << "    command)"

      param_tree.subcommands.each do |subcommand_name, subcommand_tree|
        sub_function_name = "#{function_name}_#{subcommand_name}"
        lines << "      #{subcommand_name})"
        lines << "        #{sub_function_name}"
        lines << "        ;;"
        lines << ""
      end

      lines << "      *)"
      lines << "        ;;"
      lines << "    esac"
      lines << "  ;;"

      # Create subcommand functions
      param_tree.subcommands.each do |subcommand_name, subcommand_tree|
        sub_function_name = "#{function_name}_#{subcommand_name}"
        sub_function = create_completion_function(cmd_name, subcommand_tree, option_help, sub_function_name)
        lines << "\n" + sub_function
      end

      lines.join("\n")
    end

    def parse_params : Tuple(CommandParams, Hash(String, String))
      # This creates a parameter tree (CommandParam object) for the target docopt tool.
      # Also returns a second parameter, a hash of:
      #   option -> option-help-string
      options = Docopt.parse_defaults(@doc)
      option_help = Hash(String, String).new

      options.each do |option|
        if !option.short.nil?
          option_help[option.short.to_s] = option.description
        end
        if !option.long.nil?
          option_help[option.long.to_s] = option.description
        end
      end

      pattern = Docopt.parse_pattern(
        Docopt.formal_usage(@usage), options)
      param_tree = CommandParams.new
      build_command_tree(pattern, param_tree)
      {param_tree, option_help}
    end

    # ameba:disable Metrics/CyclomaticComplexity
    def build_command_tree(pattern : Docopt::Pattern, cmd_params : CommandParams) : CommandParams
      # Recursively fill in a command tree in cmd_params according to a docopt-parsed "pattern" object.
      case pattern
      when Docopt::Either, Docopt::Optional, Docopt::OneOrMore
        if !pattern.children.nil?
          pattern.children.as(Array(Docopt::Pattern)).each do |child|
            build_command_tree(child, cmd_params)
          end
        end
      when Docopt::Required
        if !pattern.children.nil?
          pattern.children.as(Array(Docopt::Pattern)).each do |child|
            cmd_params = build_command_tree(child, cmd_params)
          end
        end
      when Docopt::Option
        suffix = pattern.argcount > 0 ? "=" : ""
        cmd_params.options << "#{pattern.short}#{suffix}" if pattern.short
        cmd_params.options << "#{pattern.long}#{suffix}" if pattern.long
      when Docopt::Command
        cmd_params = cmd_params.get_subcommand(pattern.name.to_s)
      when Docopt::Argument
        cmd_params.arguments << pattern.name.to_s
      end
      cmd_params
    end

    def get_completion_file_content(cmd : String, param_tree : CommandParams, option_help : Hash(String, String)) : String
      # ZSH completions use a more structured approach with state machines
      completion_function = create_completion_function(cmd, param_tree, option_help)

      # Add compdef registration
      "#compdef #{cmd}\n# ZSH completion for #{cmd}\n# Generated by docopt.cr\n\n#{completion_function}\n\n_#{cmd} \"$@\""
    end
  end

  def zsh_completion(
    cmd : String,
    help : String,
    custom_completions = {} of String => String
  ) : String
    completion = ZshCompletion.new help, custom_completions
    param_tree, option_help = completion.parse_params
    completion.get_completion_file_content(cmd, param_tree, option_help)
  end
end