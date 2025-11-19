require "./docopt"

# Fish shell completion generation for docopt
#
# This module provides Fish shell completion functionality by leveraging
# the same parsing infrastructure as the bash completion.

module Docopt
  extend self

  class FishCompletion
    @doc : String
    @usage : String
    @custom_completions : Hash(String, String)

    def initialize(@doc, @custom_completions = {} of String => String)
      @usage = Docopt.parse_section("usage:", @doc)[0]
    end

    def get_completion_path : String
      "~/.config/fish/completions"
    end

    def get_completion_filepath(cmd : String) : String
      "#{get_completion_path}/#{cmd}.fish"
    end

    def sanitize_name(name : String) : String
      # Fish shell has stricter requirements for function names
      name.gsub(/[^a-zA-Z0-9_]/, "_")
    end

    def create_completion_condition(command_parts : Array(String)) : String
      # Create a condition for when this completion should trigger
      # Example: "__fish_seen_subcommand_from ship new"
      return "__fish_use_subcommand" if command_parts.empty?

      conditions = [] of String
      command_parts.each do |part|
        conditions << "__fish_seen_subcommand_from #{part}"
      end
      conditions.join(" and ")
    end

    def create_option_completions(options : Array(String), option_help : Hash(String, String), command_parts : Array(String)) : String
      return "" if options.empty?

      completions = [] of String
      condition = create_completion_condition(command_parts)

      options.each do |option|
        description = option_help[option]? || option
        if option.starts_with?("--")
          # Long option
          completions << "complete -c #{command_parts.first} -l #{option[2..]} -d '#{description}'"
        elsif option.starts_with?("-") && option.size > 1
          # Short option
          completions << "complete -c #{command_parts.first} -s #{option[1]} -d '#{description}'"
        end
      end

      completions.join("\n")
    end

    def create_command_completions(subcommands : Hash(String, CommandParams), command_parts : Array(String), option_help : Hash(String, String)) : String
      return "" if subcommands.empty?

      completions = [] of String
      condition = create_completion_condition(command_parts)

      subcommands.each do |subcommand_name, subcommand_tree|
        completions << "complete -c #{command_parts.first} -f -n '#{condition}' -a #{subcommand_name} -d '#{subcommand_name}'"
      end

      completions.join("\n")
    end

    def create_argument_completions(arguments : Array(String), command_parts : Array(String), custom_name : String) : String
      return "" if arguments.empty?

      condition = create_completion_condition(command_parts)

      # Check for custom completion first
      if @custom_completions.has_key?(custom_name)
        custom_completion = @custom_completions[custom_name]
        return "complete -c #{command_parts.first} -f -n '#{condition}' -a '#{custom_completion}'"
      end

      # Default to file completion for arguments
      "complete -c #{command_parts.first} -f -n '#{condition}' -a '(ls)'"
    end

    def create_section(cmd_name : String, param_tree : CommandParams, option_help : Hash(String, String), command_parts : Array(String) = [] of String) : String
      result = [] of String
      current_command_parts = command_parts.empty? ? [cmd_name] : command_parts

      # Create subcommand completions
      unless param_tree.subcommands.empty?
        result << create_command_completions(param_tree.subcommands, current_command_parts, option_help)

        # Recursively create completions for subcommands
        param_tree.subcommands.each do |subcommand_name, subcommand_tree|
          new_command_parts = current_command_parts + [subcommand_name]
          custom_name = new_command_parts.join("_")
          result << create_section(cmd_name, subcommand_tree, option_help, new_command_parts)
        end
      end

      # Create option completions
      result << create_option_completions(param_tree.options, option_help, current_command_parts)

      # Create argument completions
      custom_name = current_command_parts.join("_")
      result << create_argument_completions(param_tree.arguments, current_command_parts, custom_name)

      result.reject(&.empty?).join("\n\n")
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
      # Fish completions use a different structure than bash
      # They work with conditions and individual complete commands
      completion_content = create_section(cmd, param_tree, option_help)

      # Add header comment
      "# Fish completion for #{cmd}\n# Generated by docopt.cr\n\n#{completion_content}"
    end
  end

  def fish_completion(
    cmd : String,
    help : String,
    custom_completions = {} of String => String
  ) : String
    completion = FishCompletion.new help, custom_completions
    param_tree, option_help = completion.parse_params
    completion.get_completion_file_content(cmd, param_tree, option_help)
  end
end