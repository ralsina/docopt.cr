require "./docopt"

# This code is a strightforward port of infi.dot_completion and
# this is the original license.
#
# Copyright (c) 2017 INFINIDAT

# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:

# 1. Redistributions of source code must retain the above copyright notice, this
#    list of conditions and the following disclaimer.

# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.

# 3. Neither the name of the copyright holder nor the names of its contributors
#    may be used to endorse or promote products derived from this software
#    without specific prior written permission.

# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

module Docopt
  extend self

  class CommandParams
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

    property arguments : Array(String) = [] of String
    property options : Array(String) = [] of String
    property subcommands : Hash(String, CommandParams) = Hash(String, CommandParams).new

    def get_subcommand(subcommand : String) : CommandParams
      subcommands[subcommand] ||= CommandParams.new
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

  class BashCompletion
    @doc : String
    @usage : String
    @custom_completions : Hash(String, String)

    def initialize(@doc, @custom_completions = {} of String => String)
      @usage = Docopt.parse_section("usage:", @doc)[0]
    end

    def get_completion_path : String
      "/etc/bash_completion.d"
    end

    def get_completion_filepath(cmd : String) : String
      completion_path = get_completion_path
      "#{completion_path}/#{cmd}.sh"
    end

    def create_subcommand_switch(cmd_name : String, level_num : Int32, subcommands : Array(String), opts : Array(String)) : String
      return "" if subcommands.empty?

      # CASE_TEMPLATE original mustache:
      #
      #     {0})
      #     _{1}_{0}
      # ;;
      subcommand_cases = subcommands.map { |subcommand|
        "            #{subcommand})
            _#{cmd_name}_#{subcommand}
        ;;"
      }.join("\n")

      # SUBCOMMAND_SWITCH_TEMPLATE. Original mustache:
      #     else
      #         case ${{COMP_WORDS[{level_num}]}} in
      # {subcommand_cases}
      #     esac
      <<-TMPL
    else
        case ${COMP_WORDS[#{level_num}]} in
#{subcommand_cases}
        esac
TMPL
    end

    def create_compreply(param_tree : CommandParams) : String
      # Add -f (show files in completion options) if there are arguments in the current section
      # In this case, there are (usually) no subcommands to suggest, and only flags, so it's ok to suggest files.
      # If the user types "-" first, then only the flags will be suggested.
      flag = param_tree.arguments.size > 0 ? "-fW" : "-W"
      word_list = (param_tree.options + param_tree.subcommands.keys).join(" ")
      "#{flag} '#{word_list}'"
    end

    def create_section(cmd_name : String, param_tree : CommandParams, option_help : Hash(String, String), level_num : Int32) : String
      subcommands = param_tree.subcommands
      opts = param_tree.options
      subcommand_switch = create_subcommand_switch(cmd_name, level_num, subcommands.keys, opts)
      op = subcommands.empty? ? "ge" : "eq"

      if @custom_completions.keys.includes? cmd_name
        compreply = "-W \"#{@custom_completions[cmd_name]}\""
      else
        compreply = create_compreply(param_tree)
      end

      # SECTION_TEMPLATE (original mustache)
      #
      # _{cmd_name}()
      # {{
      #     local cur
      #     cur="${{COMP_WORDS[COMP_CWORD]}}"

      #     if [ $COMP_CWORD -{op} {level_num} ]; then
      #         COMPREPLY=( $( compgen {compreply} -- $cur) ){subcommand_switch}
      #     fi
      # }}

      res = <<-TMPL

_#{cmd_name}()
{
    local cur
    cur="${COMP_WORDS[COMP_CWORD]}"

    if [ $COMP_CWORD -#{op} #{level_num} ]; then
        COMPREPLY=( $( compgen #{compreply} -- $cur) )#{subcommand_switch}
    fi
}
TMPL

      subcommands.each do |subcommand_name, subcommand_tree|
        res += create_section("#{cmd_name}_#{subcommand_name}", subcommand_tree, option_help, level_num + 1)
      end

      res
    end

    def sanitize_name(name : String) : String
      # Some bash versions don't support ".", "-", etc. in function names
      valid_chars = ('a'..'z').to_a + ('A'..'Z').to_a + ('0'..'9').to_a + ["_"]
      name.chars.select { |char| valid_chars.includes?(char) }.join
    end

    def get_completion_file_content(cmd : String, param_tree : CommandParams, option_help : Hash(String, String)) : String
      completion_file_inner_content = create_section(sanitize_name(cmd), param_tree, option_help, 1)

      # FILE_TEMPLATE
      # Original mustache:
      #
      #  {0}\ncomplete -o bashdefault -o default -o filenames -F _{1} {2}

      %(#{completion_file_inner_content}
complete -o bashdefault -o default -o filenames -F _#{sanitize_name(cmd)} #{cmd}
)
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
  end

  def bash_completion(
    cmd : String,
    help : String,
    custom_completions = {} of String => String
  ) : String
    completion = BashCompletion.new help, custom_completions
    param_tree, option_help = completion.parse_params
    completion.get_completion_file_content(cmd, param_tree, option_help)
  end
end
