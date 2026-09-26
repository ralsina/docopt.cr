require "./completion"

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
# DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR
# ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
# SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
# CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
# OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
# OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

module Docopt
  extend self

  class BashCompletion < Completion
    def completion_path : String
      "/etc/bash_completion.d"
    end

    def get_completion_filepath(cmd : String) : String
      "#{completion_path}/#{cmd}.sh"
    end

    # Some bash versions don't support ".", "-", etc. in function
    # names; drop them (underscores are kept).
    def sanitize_name(name : String) : String
      name.chars.select { |char| char.ascii_alphanumeric? || char == '_' }.join
    end

    # The compgen arguments completing the words valid at this node:
    # the declared options and the subcommands, plus files when the
    # node takes positional arguments. A custom completion for the
    # whole node replaces the list, like in the original port.
    private def compreply_for(cmd_name : String, param_tree : CommandParams) : String
      if custom = @custom_completions[cmd_name]?
        "-W \"#{custom}\""
      else
        flag = param_tree.arguments.size > 0 ? "-fW" : "-W"
        word_list = (param_tree.option_specs.flat_map(&.words) + param_tree.subcommands.keys).join(" ")
        "#{flag} '#{word_list}'"
      end
    end

    # Cases completing the value of options that take one, based on
    # the word being completed: "--opt=<TAB>" offers every
    # "opt=value" for word-list customs.
    private def create_attached_value_cases(param_tree : CommandParams) : String
      cases = [] of String
      param_tree.option_specs.each do |spec|
        next unless spec.takes_value?
        next if (custom = custom_for(spec)).nil? || custom.includes?("$(")
        long_name = spec.long
        next if long_name.nil?
        attached = custom.split.map { |word| "#{long_name}=#{word}" }.join(" ")
        cases << <<-CASE
              case $cur in
                  #{long_name}=*)
                      COMPREPLY=( $( compgen -W '#{attached}' -- $cur) )
                      return 0
                      ;;
              esac

          CASE
      end
      cases.join
    end

    # Cases completing the value of options that take one, based on
    # the previous word: "--opt <TAB>" (or "-o <TAB>") offers the
    # custom words, or files when there is no custom completion.
    private def create_previous_value_cases(param_tree : CommandParams) : String
      cases = [] of String
      param_tree.option_specs.each do |spec|
        next unless spec.takes_value?
        labels = [spec.long, spec.short].compact
        next if labels.empty?
        completion = if custom = custom_for(spec)
                       "compgen -W \"#{custom}\" -- $cur"
                     else
                       "compgen -f -- $cur"
                     end
        cases << <<-CASE
                  #{labels.join("|")})
                      COMPREPLY=( $( #{completion}) )
                      return 0
                      ;;
          CASE
      end
      return "" if cases.empty?
      <<-CASE
        case $prev in
        #{cases.join}        esac

        CASE
    end

    # The else branch for nodes with subcommands: walk the words
    # already on the line and hand over to the deepest subcommand
    # function that matches, so subcommands are still found when
    # positional arguments sit between them ("prog <name> move ...").
    # With no match, complete as if still at this node.
    private def create_subcommand_dispatch(cmd_name : String, level_num : Int32, subcommands : Array(String), compreply : String) : String
      return "" if subcommands.empty?
      cases = subcommands.map do |subcommand|
        "                #{subcommand}) next=\"_#{cmd_name}_#{subcommand}\" ;;"
      end.join("\n")
      <<-DISPATCH
        else
            local next="" word
            for word in "${COMP_WORDS[@]:#{level_num}:$((COMP_CWORD-#{level_num}))}"; do
                case $word in
        #{cases}
                esac
            done
            if [ -n "$next" ]; then
                $next
            else
                COMPREPLY=( $( compgen #{compreply} -- $cur) )
            fi
        DISPATCH
    end

    def create_section(cmd_name : String, param_tree : CommandParams, option_help : Hash(String, String), level_num : Int32) : String
      subcommands = param_tree.subcommands
      compreply = compreply_for(cmd_name, param_tree)
      dispatch = create_subcommand_dispatch(cmd_name, level_num, subcommands.keys, compreply)
      op = subcommands.empty? ? "ge" : "eq"

      section = String.build do |io|
        io << "\n"
        io << "_#{cmd_name}()\n"
        io << "{\n"
        io << "    local cur prev\n"
        io << "    cur=\"${COMP_WORDS[COMP_CWORD]}\"\n"
        io << "    prev=\"${COMP_WORDS[COMP_CWORD-1]}\"\n"
        io << "\n"
        io << create_attached_value_cases(param_tree)
        io << create_previous_value_cases(param_tree)
        io << "    if [ $COMP_CWORD -#{op} #{level_num} ]; then\n"
        io << "        COMPREPLY=( $( compgen #{compreply} -- $cur) )\n"
        io << dispatch
        io << "    fi\n"
        io << "}\n"
      end

      subcommands.each do |subcommand_name, subcommand_tree|
        section += create_section("#{cmd_name}_#{subcommand_name}", subcommand_tree, option_help, level_num + 1)
      end
      section
    end

    def get_completion_file_content(cmd : String, param_tree : CommandParams, option_help : Hash(String, String)) : String
      name = sanitize_name(cmd)
      "#{create_section(name, param_tree, option_help, 1)}\ncomplete -o bashdefault -o default -o filenames -F _#{name} #{cmd}\n"
    end
  end

  def bash_completion(
    cmd : String,
    help : String,
    custom_completions = {} of String => String,
  ) : String
    completion = BashCompletion.new help, custom_completions
    param_tree, option_help = completion.parse_params
    completion.get_completion_file_content(cmd, param_tree, option_help)
  end
end
