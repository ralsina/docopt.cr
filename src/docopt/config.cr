require "../docopt"
require "yaml"

module Docopt
  # The value type Docopt.docopt itself returns in its hash.
  alias DocoptValue = String | Int32 | Bool | Array(String)

  # The type of a docopt option value: what Docopt.docopt returns in its
  # hash, plus Int64/Float64 which config files and defaults can supply for
  # values docopt itself would only carry as strings.
  alias OptionValue = String | Int32 | Int64 | Float64 | Bool | Array(String)

  # Raised instead of exiting when docopt_config is called with exit: false
  # and the process would have terminated normally (help or version request).
  # Note: this class deliberately has no custom initialize — adding one breaks
  # Docopt's internal exception-class dispatch.
  class ConfigExit < DocoptException; end

  # A usage text pre-parsed for `docopt_config`: the docopt `Compiled`
  # pattern plus, lazily, the defaults-stripped copy that argv is
  # matched against, so "given on the command line" can be told apart
  # from "fell back to the declared default".
  #
  # Build one at runtime with `ConfigCompiled.parse(doc)`, or embed
  # one at compile time with the `Docopt.compile_config` macro, and
  # pass it to `Docopt.docopt_config` to skip the usage-text parsing
  # on every run.
  class ConfigCompiled
    getter compiled : Compiled
    @without_defaults : Compiled?

    def initialize(@compiled : Compiled)
    end

    def self.parse(doc : String) : ConfigCompiled
      new(Docopt.parse(doc))
    end

    # The same pattern with declared option defaults neutralized,
    # computed once on first use.
    def without_defaults : Compiled
      if stripped = @without_defaults
        stripped
      else
        @without_defaults = @compiled.without_defaults
      end
    end
  end

  class ConfigOptions
    # Values as docopt itself produces them; only defaults and config/env
    # sources can widen to Int64/Float64 (see OptionValue).
    property args : Hash(String, DocoptValue?)
    property docopt_defaults : Hash(String, OptionValue?)
    property config_file : Hash(String, YAML::Any)?
    property env_vars : Hash(String, String)

    def initialize(@args, @docopt_defaults, @config_file = nil, @env_vars = Hash(String, String).new)
    end

    # Get a configuration value with precedence: CLI > env vars > config file > docopt defaults
    def [](key : String) : OptionValue?
      # Check CLI arguments first. Flags not given parse as false and
      # repeatable options not given parse as [], so neither counts as
      # user-provided and the lower tiers get a chance to answer.
      return @args[key] if provided_by_cli?(key)

      # Check environment variables second (env keys are always long form)
      return env_value(key) if @env_vars.has_key?(long_key(key))

      # Check config file third
      if config = @config_file
        config_candidates(key).each do |candidate|
          return config_value(config[candidate]) if config.has_key?(candidate)
        end
      end

      # Finally return docopt default
      if @docopt_defaults.has_key?(key)
        return @docopt_defaults[key]
      end

      # If not found anywhere, return nil
      nil
    end

    def []?(key : String) : OptionValue?
      self[key]
    end

    # Whether the key resolves to a value from any tier, consistent with []:
    # CLI, env vars, config file (with key fallbacks) and docopt defaults.
    def has_key?(key : String) : Bool
      return true if provided_by_cli?(key)
      return true if @env_vars.has_key?(long_key(key))
      if config = @config_file
        return true if config_candidates(key).any? { |candidate| config.has_key?(candidate) }
      end
      @docopt_defaults.has_key?(key)
    end

    # Candidate config-file keys for an option key, most specific first:
    # the exact key ("--input-file"), the clean key ("input-file"), and the
    # snake_case key ("input_file"). Short options ("-v") clean to "v".
    private def config_candidates(key : String) : Array(String)
      clean_key = key.gsub(/^-+/, "")
      [key, clean_key, clean_key.gsub(/-/, "_")].uniq
    end

    # The effective configuration (every option declared in the doc,
    # resolved through the full precedence chain) as YAML text. Keys are
    # snake_case so the output can be used as a config file directly;
    # options that resolve to nil are omitted.
    def to_config_yaml : String
      result = Hash(String, OptionValue?).new
      (@args.keys + @docopt_defaults.keys).uniq.each do |key|
        next unless key.starts_with?("-")
        value = self[key]
        result[config_name(key)] = value unless value.nil?
      end
      result.to_yaml
    end

    # snake_case name for an option key: "--input-file" becomes "input_file".
    private def config_name(key : String) : String
      key.gsub(/^-+/, "").gsub(/-/, "_")
    end

    # Normalize an option key to long form ("-v" becomes "--v"), which is
    # the shape environment variables are stored under.
    private def long_key(key : String) : String
      key.starts_with?("--") ? key : "--" + key.lstrip('-')
    end

    # Whether the key was actually given on the command line, as opposed to
    # being docopt's representation of "not given" (false for flags, [] for
    # repeatable options, 0 for repeatable flags/commands).
    private def provided_by_cli?(key : String) : Bool
      return false unless @args.has_key?(key)
      case value = @args[key]
      when Bool  then value == true
      when Int32 then value != 0
      when Array then !value.empty?
      else            !value.nil?
      end
    end

    # Environment variables are strings; coerce them to the type docopt
    # would produce for the option, based on how the CLI parse typed the
    # key: Bool for flags, Int32 for repeatable flags/commands, arrays
    # (comma separated) for repeatable options, raw strings otherwise.
    private def env_value(key : String) : OptionValue?
      raw = @env_vars[long_key(key)]
      case @args[key]?
      when Bool
        case raw.downcase
        when "true", "yes", "1" then true
        when "false", "no", "0" then false
        else                         raw
        end
      when Int32
        raw.to_i32? || raw
      when Array
        raw.split(",").map(&.strip).reject(&.empty?)
      else
        raw
      end
    end

    # Convert a YAML config value to an option value. Sequences become
    # Array(String) so repeatable options can be set from the config file.
    # Numbers keep their magnitude: Int64 that fits an Int32 is narrowed,
    # otherwise (and for floats) the original type is preserved.
    private def config_value(value : YAML::Any) : OptionValue?
      case value.raw
      when String
        value.as_s
      when Bool
        value.as_bool
      when Int64
        int = value.as_i64
        (int >= Int32::MIN && int <= Int32::MAX) ? int.to_i32 : int
      when Float64
        value.as_f
      when Array
        value.as_a.map do |element|
          element.raw.is_a?(String) ? element.as_s : element.to_s
        end
      else
        value.to_s
      end
    end
  end

  # Helper method to convert environment variable names to option format
  private def self.env_to_key(key : String) : String
    "--" + key.downcase.gsub(/_+/, "-")
  end

  # Collect the environment variables relevant to options, converted to
  # option format. A nil prefix (legacy default) maps every environment
  # variable; an empty prefix means "no environment variables at all";
  # any other prefix maps only variables starting with "#{env_prefix}_"
  # (prefix stripped).
  private def self.collect_env_vars(env_prefix : String?) : Hash(String, String)
    env_vars = Hash(String, String).new
    ENV.each do |key, value|
      if env_prefix.nil?
        env_vars[env_to_key(key)] = value
      elsif !env_prefix.empty? && key.starts_with?(env_prefix + "_")
        env_vars[env_to_key(key[env_prefix.size + 1..-1])] = value
      end
    end
    env_vars
  end

  # Remove the first occurrence of option from argv, considering only
  # tokens before the "--" separator. Returns nil if it is not present.
  private def self.remove_print_config(argv : Array(String), option : String) : Array(String)?
    limit = argv.index("--") || argv.size
    pos = argv[0, limit].index(option)
    return unless pos
    stripped = argv.dup
    stripped.delete_at(pos)
    stripped
  end

  # Split the print-config flag off argv (only before a "--" separator),
  # returning the argv to parse and whether printing was requested.
  private def self.split_print_config(argv : Array(String), option : String?) : Tuple(Array(String), Bool)
    return argv, false unless option
    stripped = remove_print_config(argv, option)
    stripped ? {stripped, true} : {argv, false}
  end

  # Write the effective configuration as YAML to io and terminate (or raise
  # ConfigExit when exit is false). Does nothing unless requested.
  private def self.emit_print_config(options : ConfigOptions, requested : Bool, exit : Bool, io : IO) : Nil
    return unless requested
    io.puts options.to_config_yaml
    Process.exit(0) if exit
    raise ConfigExit.new("print-config requested")
  end

  # Handle --help / --version based on the parsed arguments, like docopt's
  # own extras(): only options actually declared in the doc trigger them,
  # and tokens after "--" (parsed as positionals) never do. Exits (or
  # raises ConfigExit when exit is false) after writing to io.
  private def self.handle_help_and_version(args : Hash(String, OptionValue?), doc : String,
                                           help : Bool, version : String?, exit : Bool, io : IO) : Nil
    if help && (args["--help"]? == true || args["-h"]? == true)
      io.puts doc
      Process.exit(0) if exit
      raise ConfigExit.new("help requested")
    end

    if version && args["--version"]? == true
      io.puts version
      Process.exit(0) if exit
      raise ConfigExit.new("version requested")
    end
  end

  # Parse a docopt usage text plus argv with config file and environment
  # variable support. The doc is parsed once per call; when the same doc
  # is used repeatedly, parse it once with `ConfigCompiled.parse` (or at
  # compile time with `Docopt.compile_config`) and pass that instead.
  def self.docopt_config(doc : String,
                         argv : Array(String) = ARGV,
                         config_file_path : String? = nil,
                         env_prefix : String? = nil,
                         help : Bool = true,
                         version : String? = nil,
                         options_first : Bool = false,
                         exit : Bool = true,
                         io : IO = STDOUT,
                         print_config_option : String? = nil) : ConfigOptions
    docopt_config(ConfigCompiled.parse(doc), argv, config_file_path, env_prefix,
      help, version, options_first, exit, io, print_config_option)
  end

  # Main function to match argv against an already parsed usage text
  # with config file and environment variable support.
  #
  # One linear flow: match, tiers, collect, and the exit/rescue
  # handling the tool contract asks for.
  # ameba:disable Metrics/CyclomaticComplexity
  def self.docopt_config(pattern : ConfigCompiled,
                         argv : Array(String) = ARGV,
                         config_file_path : String? = nil,
                         env_prefix : String? = nil,
                         help : Bool = true,
                         version : String? = nil,
                         options_first : Bool = false,
                         exit : Bool = true,
                         io : IO = STDOUT,
                         print_config_option : String? = nil) : ConfigOptions
    begin
      # The print-config flag is stripped before parsing so it does not
      # need to be declared in the doc.
      parse_argv, print_requested = split_print_config(argv, print_config_option)

      # argv is matched against the defaults-stripped pattern so that
      # options absent from the command line read as not provided; the
      # declared defaults are a separate, lowest-precedence tier.
      args = Docopt.match(
        pattern.without_defaults,
        argv: parse_argv,
        help: false,  # Help is handled here, not by docopt
        version: nil, # Version is handled here, not by docopt
        options_first: options_first,
        exit: false
      )

      handle_help_and_version(args, pattern.compiled.doc, help, version, exit, io)

      # Extract declared defaults from the same parse
      docopt_defaults = extract_docopt_defaults(pattern.compiled)

      # Parse config file if provided
      config_file : Hash(String, YAML::Any)? = nil
      if config_file_path && File.exists?(config_file_path)
        begin
          config_content = File.read(config_file_path)
          yaml_data = YAML.parse(config_content).as_h
          # Convert YAML keys to strings
          stringified_config = Hash(String, YAML::Any).new
          yaml_data.each do |key, value|
            stringified_config[key.as_s] = value
          end
          config_file = stringified_config
        rescue ex
          # A config file that can't be parsed is very likely a mistake;
          # say so instead of silently running without it.
          STDERR.puts "docopt-config: warning: ignoring config file #{config_file_path}: #{ex.message}"
          config_file = nil
        end
      end

      # Get relevant environment variables
      env_vars = collect_env_vars(env_prefix)

      options = ConfigOptions.new(args, docopt_defaults, config_file, env_vars)
      emit_print_config(options, print_requested, exit, io)
      options
    rescue ex : DocoptExit
      # Usage error: docopt convention is an optional message plus the usage
      # summary on stderr, and a non-zero exit status. The usage comes from
      # the pattern being matched, not from global state.
      if exit
        message = ex.message
        STDERR.puts message if message && !message.empty?
        usage = pattern.compiled.usage
        STDERR.puts usage unless usage.empty?
        Process.exit(1)
      end
      raise ex
    rescue ex
      # Handle other exceptions
      if exit
        STDERR.puts "Error: #{ex.message}"
        Process.exit(1)
      end
      raise ex
    end
  end

  # The declared [default: ...] tier, extracted from the compiled
  # pattern: options that take a value (long or short only), with the
  # raw default coerced the way config values are (booleans, integers,
  # floats, quoted strings). Repeated options keep the array docopt
  # itself would produce for them. Falsy defaults ([default: false])
  # stay absent, like before.
  private def self.extract_docopt_defaults(compiled : Compiled) : Hash(String, OptionValue?)
    defaults = Hash(String, OptionValue?).new
    compiled.defaults.each do |key, value|
      case value
      when Array(String)
        defaults[key] = value
      when String
        parsed_value = parse_default_value(value)
        defaults[key] = parsed_value if parsed_value
      end
    end
    defaults
  end

  # Parse default value to appropriate type
  private def self.parse_default_value(value : String) : OptionValue?
    case value.downcase
    when "true", "yes"
      true
    when "false", "no"
      false
    when /^\d+$/
      value.to_i32? || value.to_i64
    when /^\d+\.\d+$/
      value.to_f
    when /^".*"$/, /^'.*'/
      value[1..-2] # Remove quotes
    else
      value
    end
  end

  # Parse a docopt usage text for docopt_config at compile time.
  #
  # *doc* must be a string literal, or a constant assigned one. The
  # text is parsed while compiling and the resulting pattern is
  # embedded in the program, so at runtime only argv matching and the
  # config/env tiers run. An invalid usage text is a compilation
  # error.
  #
  # ```
  # USAGE = <<-DOC
  #   Usage: prog [--verbose=<level>]
  #   DOC
  #
  # CONFIG = Docopt.compile_config(USAGE)
  # options = Docopt.docopt_config(CONFIG, argv: ARGV, env_prefix: "PROG")
  # ```
  macro compile_config(doc)
    {% doc = doc.resolve if doc.is_a?(Path) %}
    {% raise "Docopt.compile_config expects a string literal or a constant holding one, got #{doc.class_name}" unless doc.is_a?(StringLiteral) %}
    {{ run("./config/compile_pattern", doc) }}
  end
end
