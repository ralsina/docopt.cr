require "./docopt"
require "crustache"

doc = <<-DOC
  Naval Fate.

  Usage:
    naval_fate init [-v]...
    naval_fate ship new <name>...
    naval_fate ship <name> move <x> <y> [--speed=<kn>]
    naval_fate ship shoot <x> <y>
    naval_fate mine (set|remove) <x> <y> [--moored|--drifting]
    naval_fate save [--files=files...]
    naval_fate set_speed [--speed=<kn>]
    naval_fate -h | --help
    naval_fate --version

  Options:
    -h --help        Show this screen.
    --version        Show version.
    -s,--speed=<kn>  Speed in knots [default: 10].
    --moored         Moored (anchored) mine.
    --drifting       Drifting mine.
DOC

usage_section = Docopt.parse_section("usage:", doc)[0]
options = Docopt.parse_defaults(doc)
pattern = Docopt.parse_pattern(Docopt.formal_usage(usage_section), options)

FILE_TEMPLATE = Crustache.parse "{{0}}\ncomplete -o bashdefault -o default -o filenames -F _{{1}} {{2}}"

SECTION_TEMPLATE = Crustache.parse <<-TMPL
_{{cmd_name}}()
\{{
    local cur
    cur="$\{{COMP_WORDS[COMP_CWORD]}}"

    if [ $COMP_CWORD -{{op}} {{level_num}} ]; then
        COMPREPLY=( $( compgen {{compreply}} -- $cur) ){{subcommand_switch}}
    fi
}}
TMPL

SUBCOMMAND_SWITCH_TEMPLATE = Crustache.parse <<-TMPL
    else
        case $\{{COMP_WORDS[{level_num}]}} in
{{subcommand_cases}}
        esac
TMPL

CASE_TEMPLATE = Crustache.parse <<-TMPL
            {{0}})
            _{{1}}_{{0}}
        ;;
TMPL

