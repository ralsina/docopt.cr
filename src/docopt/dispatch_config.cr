require "./dispatch"
require "./config"

# Dispatch plus configuration: the same subcommand dispatch, with every
# command's options resolved through the docopt-config precedence
# chain (CLI > environment > config file > docopt defaults).
#
# Requiring this file pulls in both layers; commands read resolved
# values through their usual options hash.

module Docopt
  module Dispatch
    # Like `Dispatch.main`, but each command's options resolve through
    # the full precedence chain before `run` sees them: command line
    # first, then environment variables (mapped from *env_prefix*),
    # then the YAML file at *config_file_path*, then the doc's
    # declared defaults.
    #
    # Resolved values are normalized to the types docopt itself would
    # produce, so commands keep reading `options["--flag"]`,
    # `options["-p"]` and friends unchanged: config-file floats and
    # overflowing integers arrive as the strings docopt would have
    # parsed, integers that fit stay integers.
    #
    # When *print_config_option* is given (e.g. "--print-config"), a
    # command invoked with that flag prints its fully-resolved
    # configuration as YAML and exits 0, like docopt_config does for
    # single-doc tools.
    def self.config_main(progname : String, args : Array(String),
                         config_file_path : String? = nil,
                         env_prefix : String? = nil,
                         print_config_option : String? = nil,
                         stdout : IO = STDOUT, stderr : IO = STDERR) : Int32
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
        options = Docopt.docopt_config(
          ConfigCompiled.new(command.compiled),
          argv: args,
          config_file_path: config_file_path,
          env_prefix: env_prefix,
          help: false, # dispatch handles help itself
          version: nil,
          exit: false,
          io: stdout,
          print_config_option: print_config_option
        )
      rescue Docopt::ConfigExit
        # --print-config: the YAML was already written to io
        return 0
      rescue error : Docopt::DocoptLanguageError
        stderr.puts "Invalid documentation for command '#{command_name}': #{error.message}"
        return 1
      rescue Docopt::DocoptExit
        stderr.puts command.compiled.usage
        stderr.puts
        stderr.puts "See '#{progname} help #{command_name}' for more information."
        return 1
      end

      command.new(resolved_options(options)).run
    end

    # The precedence-resolved values as the plain options hash
    # commands expect, normalized to docopt's own value types.
    private def self.resolved_options(options : ConfigOptions) : Hash(String, (String | Int32 | Bool | Array(String))?)
      resolved = Hash(String, (String | Int32 | Bool | Array(String))?).new
      (options.args.keys + options.docopt_defaults.keys).uniq.each do |key|
        value = options[key]
        case value
        when Int64
          fits = value >= Int32::MIN && value <= Int32::MAX
          resolved[key] = fits ? value.to_i32 : value.to_s
        when Float64
          resolved[key] = value.to_s
        when String | Int32 | Bool | Array(String)
          resolved[key] = value
        end
      end
      resolved
    end
  end
end
