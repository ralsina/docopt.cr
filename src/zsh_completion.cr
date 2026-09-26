require "./completion"

# ZSH shell completion generation for docopt
#
# This module provides ZSH shell completion functionality by leveraging
# the same parsing infrastructure shared with the bash completion.
#
# Subcommands use the canonical zsh state-machine shape: _arguments
# moves the first positional into a state, which offers the node's
# subcommands, and the remaining words dispatch to the subcommand's
# own function (matching a subcommand name anywhere in the remaining
# words, so positional arguments between subcommands still dispatch).

module Docopt
  extend self

  class ZshCompletion < Completion
    def completion_path : String
      "/usr/share/zsh/site-functions"
    end

    def get_completion_filepath(cmd : String) : String
      "#{completion_path}/_#{cmd}"
    end

    private def function_name_for(path : Array(String)) : String
      "_" + path.map { |segment| sanitize_name(segment) }.join("_")
    end

    # [ and ] would close the description bracket inside a spec.
    private def zsh_description(description : String) : String
      description.gsub(/[\[\]]/, "")
    end

    # Completion action for custom values: a literal word list in
    # parentheses, or shell code in braces for the "$(cmd)" form.
    private def value_action(custom : String?) : String?
      return if custom.nil?
      if custom.starts_with?("$(") && custom.ends_with?(")")
        "{#{custom}}"
      else
        "(#{custom.split.join(" ")})"
      end
    end

    private def plain_words(custom : String) : Array(String)
      custom.gsub("$(", "").gsub(")", "").split
    end

    # One _arguments spec per option name (short and long forms each
    # get one), with the description in brackets and, for options that
    # take a value, an action for the value.
    private def option_spec_strings(param_tree : CommandParams, option_help : Hash(String, String)) : Array(String)
      specs = [] of String
      param_tree.option_specs.each do |spec|
        next if (name = spec.name).nil?
        description = zsh_description(description_for(name, option_help))
        action = spec.takes_value? ? value_action(custom_for(spec)) : nil
        [spec.long, spec.short].compact.each do |option_name|
          base = spec.takes_value? ? "#{option_name}=" : option_name
          spec_string = "'#{base}[#{description}]'"
          spec_string = "'#{base}[#{description}]:value:#{action}'" if action
          specs << spec_string
        end
      end
      specs
    end

    private def create_function(path : Array(String), param_tree : CommandParams, option_help : Hash(String, String)) : String
      function_name = function_name_for(path)
      custom = @custom_completions[path.join("_")]?
      subcommands = param_tree.subcommands

      specs = option_spec_strings(param_tree, option_help)
      if subcommands.empty?
        param_tree.arguments.each do |argument|
          specs << "':#{argument}:#{value_action(custom) || "_files"}'"
        end
      else
        specs << (param_tree.arguments.empty? ? "':command:->command'" : "':argument:->first'")
        specs << "'*::rest:->rest'"
      end

      lines = [] of String
      lines << "#{function_name}() {"
      lines << "    local context state line"
      lines << "    typeset -A opt_args"
      lines << ""
      unless specs.empty?
        lines << "    _arguments -s -S \\"
        specs.each_with_index do |spec, index|
          lines << "        #{spec}#{index < specs.size - 1 ? " \\" : ""}"
        end
        lines << ""
      end

      unless subcommands.empty?
        lines << "    case $state in"
        if param_tree.arguments.empty?
          lines << "        (command)"
          subcommand_list = subcommands.keys.map { |name| "'#{name}'" }.join(" ")
          lines << "            _values 'command' #{subcommand_list}"
          lines << "            ;;"
        else
          lines << "        (first)"
          lines << "            _alternative \\"
          lines << "                'subcommands:subcommand:_values subcommand #{subcommands.keys.join(" ")}' \\"
          if custom
            if custom.starts_with?("$(") && custom.ends_with?(")")
              lines << "                'arguments:argument:#{value_action(custom)}'"
            else
              lines << "                'arguments:argument:_values argument #{plain_words(custom).join(" ")}'"
            end
          else
            lines << "                'arguments:argument:_files'"
          end
          lines << "            ;;"
        end
        lines << "        (rest)"
        # Walk the remaining words so a subcommand is still found when
        # positional arguments sit between subcommands (alternation in
        # a case pattern needs no extended_glob, unlike a ${...:#...}
        # parameter pattern).
        lines << "            local sub=\"\" command_word"
        lines << "            for command_word in $words; do"
        lines << "                case $command_word in"
        subcommands.each_key do |subcommand_name|
          lines << "                    (#{subcommand_name}) sub=#{subcommand_name} ;;"
        end
        lines << "                esac"
        lines << "            done"
        lines << "            case $sub in"
        subcommands.each_key do |subcommand_name|
          lines << "                (#{subcommand_name}) #{function_name_for(path + [subcommand_name])} ;;"
        end
        lines << "            esac"
        lines << "            ;;"
        lines << "    esac"
      end
      lines << "}"
      lines << ""

      subcommands.each do |subcommand_name, subcommand_tree|
        lines << create_function(path + [subcommand_name], subcommand_tree, option_help)
      end
      lines.join("\n")
    end

    def get_completion_file_content(cmd : String, param_tree : CommandParams, option_help : Hash(String, String)) : String
      "#compdef #{cmd}\n# ZSH completion for #{cmd}\n# Generated by docopt.cr\n\n#{create_function([cmd], param_tree, option_help)}\n"
    end
  end

  def zsh_completion(
    cmd : String,
    help : String,
    custom_completions = {} of String => String,
  ) : String
    completion = ZshCompletion.new help, custom_completions
    param_tree, option_help = completion.parse_params
    completion.get_completion_file_content(cmd, param_tree, option_help)
  end
end
