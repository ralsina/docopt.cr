require "./spec_helper"
require "../src/docopt/config"

# Build a config hash the same way the library does from YAML text.
def config_from_yaml(raw : String) : Hash(String, YAML::Any)
  parsed = Hash(String, YAML::Any).new
  YAML.parse(raw).as_h.each do |key, value|
    parsed[key.as_s] = value
  end
  parsed
end

describe Docopt do
  describe ".docopt_config" do
    it "parses command line arguments with docopt" do
      doc = "Usage: test [--verbose=<level>]"
      argv = ["--verbose", "2"]

      options = Docopt.docopt_config(doc, argv: argv)

      options["--verbose"].should eq("2")
    end

    it "reads from environment variables when CLI not provided" do
      doc = "Usage: test [--verbose=<level>]"
      ENV["TEST_VERBOSE"] = "5"

      begin
        options = Docopt.docopt_config(doc, env_prefix: "TEST")
        options["--verbose"].should eq("5")
      ensure
        ENV.delete("TEST_VERBOSE")
      end
    end

    it "prioritizes CLI arguments over environment variables" do
      doc = "Usage: test [--verbose=<level>]"
      argv = ["--verbose", "cli"]
      ENV["TEST_VERBOSE"] = "env"

      begin
        options = Docopt.docopt_config(doc, argv: argv, env_prefix: "TEST")
        options["--verbose"].should eq("cli")
      ensure
        ENV.delete("TEST_VERBOSE")
      end
    end

    it "handles missing values gracefully" do
      doc = "Usage: test [--verbose=<level>]"
      argv = [] of String

      options = Docopt.docopt_config(doc, argv: argv)

      options["--verbose"].should be_nil
    end

    it "supports multiple options" do
      doc = "Usage: test [--verbose=<level>] [--output=<file>]"
      argv = ["--verbose", "2"]
      ENV["TEST_OUTPUT"] = "result.txt"

      begin
        options = Docopt.docopt_config(doc, argv: argv, env_prefix: "TEST")
        options["--verbose"].should eq("2")
        options["--output"].should eq("result.txt")
      ensure
        ENV.delete("TEST_OUTPUT")
      end
    end

    it "converts environment variable names correctly" do
      doc = "Usage: test [--input-file=<path>]"
      ENV["MYAPP_INPUT_FILE"] = "/path/to/file"

      begin
        options = Docopt.docopt_config(doc, env_prefix: "MYAPP")
        options["--input-file"].should eq("/path/to/file")
      ensure
        ENV.delete("MYAPP_INPUT_FILE")
      end
    end

    it "handles basic config file" do
      doc = "Usage: test [--verbose=<level>]"
      temp_config = File.tempname("docopt-config", ".yml")
      File.write(temp_config, {"--verbose" => "1"}.to_yaml)

      begin
        options = Docopt.docopt_config(doc, config_file_path: temp_config)
        options["--verbose"].should eq("1")
      ensure
        File.delete(temp_config) if File.exists?(temp_config)
      end
    end

    it "handles snake_case config keys" do
      doc = "Usage: test [--input-file=<path>]"
      temp_config = File.tempname("docopt-config", ".yml")
      File.write(temp_config, {"input_file" => "/path/to/file.txt"}.to_yaml)

      begin
        options = Docopt.docopt_config(doc, config_file_path: temp_config)
        options["--input-file"].should eq("/path/to/file.txt")
      ensure
        File.delete(temp_config) if File.exists?(temp_config)
      end
    end

    it "handles clean config keys without dashes" do
      doc = "Usage: test [--verbose=<level>]"
      temp_config = File.tempname("docopt-config", ".yml")
      File.write(temp_config, {"verbose" => "3"}.to_yaml)

      begin
        options = Docopt.docopt_config(doc, config_file_path: temp_config)
        options["--verbose"].should eq("3")
      ensure
        File.delete(temp_config) if File.exists?(temp_config)
      end
    end

    it "handles docopt defaults when no other sources are available" do
      doc = <<-DOC
        Usage: test [--verbose=<level>]

        Options:
          --verbose=<level>  Verbosity level [default: docopt-default]
        DOC

      options = Docopt.docopt_config(doc, argv: [] of String)
      options["--verbose"].should eq("docopt-default")
    end

    it "allows environment variables to override docopt defaults" do
      doc = <<-DOC
        Usage: test [--verbose=<level>]

        Options:
          --verbose=<level>  Verbosity level [default: docopt-default]
        DOC

      ENV["TEST_VERBOSE"] = "env-different-value"

      begin
        options = Docopt.docopt_config(doc, argv: [] of String, env_prefix: "TEST")
        options["--verbose"].should eq("env-different-value")
      ensure
        ENV.delete("TEST_VERBOSE")
      end
    end

    it "allows CLI arguments to take precedence even when equal to docopt default" do
      doc = <<-DOC
        Usage: test [--verbose=<level>]

        Options:
          --verbose=<level>  Verbosity level [default: same-value]
        DOC

      ENV["TEST_VERBOSE"] = "different-value"

      begin
        options = Docopt.docopt_config(doc, argv: ["--verbose", "same-value"], env_prefix: "TEST")
        options["--verbose"].should eq("same-value")
      ensure
        ENV.delete("TEST_VERBOSE")
      end
    end

    it "allows config files to override docopt defaults" do
      doc = <<-DOC
        Usage: test [--verbose=<level>]

        Options:
          --verbose=<level>  Verbosity level [default: docopt-default]
        DOC

      temp_config = File.tempname("docopt-config", ".yml")
      File.write(temp_config, {"verbose" => "config-value"}.to_yaml)

      begin
        options = Docopt.docopt_config(doc, argv: [] of String, config_file_path: temp_config)
        options["--verbose"].should eq("config-value")
      ensure
        File.delete(temp_config) if File.exists?(temp_config)
      end
    end

    it "handles multiline option descriptions correctly" do
      doc = <<-DOC
        Usage: test [--verbose=<level>]

        Options:
          --verbose=<level>  Set the verbosity level
                            This is a longer description
                            that spans multiple lines
                            [default: multiline-default]
        DOC

      options = Docopt.docopt_config(doc, argv: [] of String)
      options["--verbose"].should eq("multiline-default")
    end

    it "handles mixed options with some having defaults and others not" do
      doc = <<-DOC
        Usage: test [--simple] [--verbose=<level>]

        Options:
          --simple         A simple flag without default
          --verbose=<level> Set the verbosity level
                            This is a longer description
                            that spans multiple lines
                            [default: mixed-default]
        DOC

      options = Docopt.docopt_config(doc, argv: [] of String)
      options["--simple"].should be_nil               # No default
      options["--verbose"].should eq("mixed-default") # Has default
    end

    it "converts integer config values to integers" do
      doc = "Usage: test [--count=<n>]"
      temp_config = File.tempname("docopt-config", ".yml")
      File.write(temp_config, {"count" => 10}.to_yaml)

      begin
        options = Docopt.docopt_config(doc, config_file_path: temp_config)
        options["--count"].should eq(10)
      ensure
        File.delete(temp_config) if File.exists?(temp_config)
      end
    end

    it "converts boolean config values to booleans" do
      doc = "Usage: test [--force]"
      temp_config = File.tempname("docopt-config", ".yml")
      File.write(temp_config, {"force" => true}.to_yaml)

      begin
        options = Docopt.docopt_config(doc, config_file_path: temp_config)
        options["--force"].should be_true
      ensure
        File.delete(temp_config) if File.exists?(temp_config)
      end
    end

    it "converts config file sequences to arrays for repeatable options" do
      doc = "Usage: test [--font=<font>...]"
      temp_config = File.tempname("docopt-config", ".yml")
      File.write(temp_config, {"font" => ["a.ttf", "b.ttf"]}.to_yaml)

      begin
        options = Docopt.docopt_config(doc, config_file_path: temp_config)
        options["--font"].should eq(["a.ttf", "b.ttf"])
      ensure
        File.delete(temp_config) if File.exists?(temp_config)
      end
    end

    it "treats a single-element config file sequence as an array" do
      doc = "Usage: test [--font=<font>...]"
      temp_config = File.tempname("docopt-config", ".yml")
      File.write(temp_config, {"font" => ["only.ttf"]}.to_yaml)

      begin
        options = Docopt.docopt_config(doc, config_file_path: temp_config)
        options["--font"].should eq(["only.ttf"])
      ensure
        File.delete(temp_config) if File.exists?(temp_config)
      end
    end

    it "stringifies non-string elements of config file sequences" do
      doc = "Usage: test [--font=<font>...]"
      temp_config = File.tempname("docopt-config", ".yml")
      File.write(temp_config, {"font" => ["a.ttf", 2]}.to_yaml)

      begin
        options = Docopt.docopt_config(doc, config_file_path: temp_config)
        options["--font"].should eq(["a.ttf", "2"])
      ensure
        File.delete(temp_config) if File.exists?(temp_config)
      end
    end

    it "keeps arrays from repeated CLI arguments for repeatable options" do
      doc = "Usage: test [--font=<font>...]"
      argv = ["--font", "cli1.ttf", "--font", "cli2.ttf"]

      options = Docopt.docopt_config(doc, argv: argv)

      options["--font"].should eq(["cli1.ttf", "cli2.ttf"])
    end

    it "implements correct precedence: CLI > env vars > config file > docopt defaults" do
      doc = <<-DOC
        Usage: test [--verbose=<level>]

        Options:
          --verbose=<level>  Verbosity level [default: docopt-default]
        DOC

      temp_config = File.tempname("docopt-config", ".yml")
      File.write(temp_config, {"verbose" => "config-value"}.to_yaml)
      ENV["TEST_VERBOSE"] = "env-value"

      begin
        # Test CLI > env vars > config file > docopt defaults
        options_cli = Docopt.docopt_config(doc, argv: ["--verbose", "cli-value"], config_file_path: temp_config, env_prefix: "TEST")
        options_cli["--verbose"].should eq("cli-value")

        # Test env vars > config file > docopt defaults (no CLI)
        options_env = Docopt.docopt_config(doc, argv: [] of String, config_file_path: temp_config, env_prefix: "TEST")
        options_env["--verbose"].should eq("env-value")

        # Test config file > docopt defaults (no CLI, no env)
        ENV.delete("TEST_VERBOSE")
        options_config = Docopt.docopt_config(doc, argv: [] of String, config_file_path: temp_config)
        options_config["--verbose"].should eq("config-value")

        # Test docopt defaults (no CLI, no env, no config)
        options_default = Docopt.docopt_config(doc, argv: [] of String)
        options_default["--verbose"].should eq("docopt-default")
      ensure
        File.delete(temp_config) if File.exists?(temp_config)
        ENV.delete("TEST_VERBOSE")
      end
    end

    it "raises ConfigExit for help requests when exit is false" do
      doc = "Usage: test [--help]\n\nOptions:\n  --help  Show help"
      io = IO::Memory.new

      expect_raises(Docopt::ConfigExit) do
        Docopt.docopt_config(doc, argv: ["--help"], exit: false, io: io)
      end

      io.to_s.should contain("Usage: test")
    end

    it "raises ConfigExit for short -h help requests when exit is false" do
      doc = "Usage: test [-h]\n\nOptions:\n  -h  Show help"
      io = IO::Memory.new

      expect_raises(Docopt::ConfigExit) do
        Docopt.docopt_config(doc, argv: ["-h"], exit: false, io: io)
      end
    end

    it "raises ConfigExit for version requests when exit is false" do
      doc = "Usage: test [--version]\n\nOptions:\n  --version  Show version"
      io = IO::Memory.new

      expect_raises(Docopt::ConfigExit) do
        Docopt.docopt_config(doc, argv: ["--version"], version: "1.2.3", exit: false, io: io)
      end

      io.to_s.should eq("1.2.3\n")
    end

    it "does not trigger help for --help after the -- separator" do
      doc = "Usage: test [<file>]\n\nOptions:\n  --help  Show help"
      io = IO::Memory.new

      # docopt.cr currently treats the -- token itself as a positional, so
      # this argv is a usage error; the point is that help is not shown.
      expect_raises(Docopt::DocoptExit) do
        Docopt.docopt_config(doc, argv: ["--", "--help"], exit: false, io: io)
      end

      io.to_s.should be_empty
    end

    it "treats an undeclared --help as a usage error" do
      doc = "Usage: test [--verbose=<level>]"
      io = IO::Memory.new

      expect_raises(Docopt::DocoptExit) do
        Docopt.docopt_config(doc, argv: ["--help"], exit: false, io: io)
      end

      io.to_s.should be_empty
    end

    it "parses normally instead of showing help when help is false" do
      doc = "Usage: test [--help]\n\nOptions:\n  --help  Show help"
      io = IO::Memory.new

      options = Docopt.docopt_config(doc, argv: ["--help"], help: false, exit: false, io: io)

      io.to_s.should be_empty
      options["--help"].should be_true
    end

    it "allows env vars to override non-lowercase [default: ...] annotations" do
      doc = <<-DOC
        Usage: test [--verbose=<level>]

        Options:
          --verbose=<level>  Verbosity level [DEFAULT: docopt-default]
        DOC

      ENV["TEST_VERBOSE"] = "env-value"

      begin
        options = Docopt.docopt_config(doc, argv: [] of String, env_prefix: "TEST")
        options["--verbose"].should eq("env-value")
      ensure
        ENV.delete("TEST_VERBOSE")
      end
    end

    it "lets a config file enable a repeatable flag not given on the CLI" do
      doc = "Usage: test [-v...]"
      temp_config = File.tempname("docopt-config", ".yml")
      File.write(temp_config, {"v" => 3}.to_yaml)

      begin
        options = Docopt.docopt_config(doc, argv: [] of String, config_file_path: temp_config)
        options["-v"].should eq(3)
      ensure
        File.delete(temp_config) if File.exists?(temp_config)
      end
    end

    it "coerces boolean env vars for flags" do
      doc = "Usage: test [--force]"
      ENV["TEST_FORCE"] = "false"

      begin
        options = Docopt.docopt_config(doc, argv: [] of String, env_prefix: "TEST")
        options["--force"].should be_false
      ensure
        ENV.delete("TEST_FORCE")
      end
    end

    it "coerces truthy env var spellings for flags" do
      doc = "Usage: test [--force]"
      ENV["TEST_FORCE"] = "yes"

      begin
        options = Docopt.docopt_config(doc, argv: [] of String, env_prefix: "TEST")
        options["--force"].should be_true
      ensure
        ENV.delete("TEST_FORCE")
      end
    end

    it "keeps unrecognized env var values for flags as strings" do
      doc = "Usage: test [--force]"
      ENV["TEST_FORCE"] = "maybe"

      begin
        options = Docopt.docopt_config(doc, argv: [] of String, env_prefix: "TEST")
        options["--force"].should eq("maybe")
      ensure
        ENV.delete("TEST_FORCE")
      end
    end

    it "splits comma separated env vars into arrays for repeatable options" do
      doc = "Usage: test [--font=<font>...]"
      ENV["TEST_FONT"] = "a.ttf, b.ttf"

      begin
        options = Docopt.docopt_config(doc, argv: [] of String, env_prefix: "TEST")
        options["--font"].should eq(["a.ttf", "b.ttf"])
      ensure
        ENV.delete("TEST_FONT")
      end
    end

    it "coerces numeric env vars into counts for repeatable flags" do
      doc = "Usage: test [-v...]"
      ENV["TEST_V"] = "3"

      begin
        options = Docopt.docopt_config(doc, argv: [] of String, env_prefix: "TEST")
        options["-v"].should eq(3)
      ensure
        ENV.delete("TEST_V")
      end
    end

    it "has_key? agrees with [] for snake_case config keys" do
      doc = "Usage: test [--input-file=<path>]"
      temp_config = File.tempname("docopt-config", ".yml")
      File.write(temp_config, {"input_file" => "/data/x.csv"}.to_yaml)

      begin
        options = Docopt.docopt_config(doc, argv: [] of String, config_file_path: temp_config)
        options["--input-file"].should eq("/data/x.csv")
        options.has_key?("--input-file").should be_true
      ensure
        File.delete(temp_config) if File.exists?(temp_config)
      end
    end

    it "has_key? counts docopt defaults as present" do
      doc = <<-DOC
        Usage: test [--verbose=<level>]

        Options:
          --verbose=<level>  Verbosity level [default: docopt-default]
        DOC

      options = Docopt.docopt_config(doc, argv: [] of String)

      options.has_key?("--verbose").should be_true
      options["--verbose"].should eq("docopt-default")
    end

    it "has_key? is false for options no source provides" do
      doc = "Usage: test [--force]"

      options = Docopt.docopt_config(doc, argv: [] of String)

      options.has_key?("--force").should be_false
      options["--force"].should be_nil
    end

    it "keeps config file floats as floats" do
      doc = "Usage: test [--ratio=<r>]"
      temp_config = File.tempname("docopt-config", ".yml")
      File.write(temp_config, {"ratio" => 2.5}.to_yaml)

      begin
        options = Docopt.docopt_config(doc, argv: [] of String, config_file_path: temp_config)
        options["--ratio"].should eq(2.5)
        options["--ratio"].should be_a(Float64)
      ensure
        File.delete(temp_config) if File.exists?(temp_config)
      end
    end

    it "keeps config file integers that overflow Int32 as Int64" do
      doc = "Usage: test [--count=<n>]"
      temp_config = File.tempname("docopt-config", ".yml")
      File.write(temp_config, {"count" => 9999999999}.to_yaml)

      begin
        options = Docopt.docopt_config(doc, argv: [] of String, config_file_path: temp_config)
        options["--count"].should eq(9999999999)
        options["--count"].should be_a(Int64)
      ensure
        File.delete(temp_config) if File.exists?(temp_config)
      end
    end

    it "keeps float docopt defaults as floats" do
      doc = <<-DOC
        Usage: test [--ratio=<r>]

        Options:
          --ratio=<r>  Aspect ratio [default: 2.5]
        DOC

      options = Docopt.docopt_config(doc, argv: [] of String)

      options["--ratio"].should eq(2.5)
      options["--ratio"].should be_a(Float64)
    end

    it "falls back gracefully when the config file is not valid YAML" do
      doc = "Usage: test [--verbose=<level>]"
      temp_config = File.tempname("docopt-config", ".yml")
      File.write(temp_config, "not: [valid: yaml")

      begin
        options = Docopt.docopt_config(doc, argv: [] of String, config_file_path: temp_config)
        options["--verbose"].should be_nil
      ensure
        File.delete(temp_config) if File.exists?(temp_config)
      end
    end

    it "falls back gracefully when the config file root is not a mapping" do
      doc = "Usage: test [--verbose=<level>]"
      temp_config = File.tempname("docopt-config", ".yml")
      File.write(temp_config, "- one\n- two\n")

      begin
        options = Docopt.docopt_config(doc, argv: [] of String, config_file_path: temp_config)
        options["--verbose"].should be_nil
      ensure
        File.delete(temp_config) if File.exists?(temp_config)
      end
    end

    it "treats an empty env prefix as no environment variables" do
      doc = "Usage: test [--verbose=<level>]"
      ENV["TEST_VERBOSE"] = "5"

      begin
        options = Docopt.docopt_config(doc, argv: [] of String, env_prefix: "")
        options["--verbose"].should be_nil
      ensure
        ENV.delete("TEST_VERBOSE")
      end
    end

    it "with a nil env prefix maps every environment variable" do
      doc = "Usage: test [--test-verbose=<level>]"
      ENV["TEST_VERBOSE"] = "5"

      begin
        options = Docopt.docopt_config(doc, argv: [] of String)
        options["--test-verbose"].should eq("5")
      ensure
        ENV.delete("TEST_VERBOSE")
      end
    end

    it "raises DocoptExit for invalid arguments when exit is false" do
      doc = "Usage: test [--verbose=<level>]"

      expect_raises(Docopt::DocoptExit) do
        Docopt.docopt_config(doc, argv: ["--verbose"], exit: false)
      end
    end

    it "propagates the usage error message when exit is false" do
      doc = "Usage: test [--verbose=<level>]"

      ex = expect_raises(Docopt::DocoptExit) do
        Docopt.docopt_config(doc, argv: ["--verbose"], exit: false)
      end

      ex.message.should eq("--verbose requires argument")
    end

    it "prints the effective configuration when the print option is given" do
      doc = "Usage: test [--verbose=<level>] [--font=<font>...]"
      ENV["TEST_VERBOSE"] = "9"
      temp_config = File.tempname("docopt-config", ".yml")
      File.write(temp_config, {"font" => ["one.ttf", "two.ttf"]}.to_yaml)
      io = IO::Memory.new

      begin
        expect_raises(Docopt::ConfigExit) do
          Docopt.docopt_config(doc, argv: ["--print-config"], config_file_path: temp_config,
            env_prefix: "TEST", print_config_option: "--print-config", exit: false, io: io)
        end

        yaml = YAML.parse(io.to_s)
        yaml["verbose"].should eq("9")                                  # env tier
        yaml["font"].as_a.map(&.as_s).should eq(["one.ttf", "two.ttf"]) # config tier
      ensure
        File.delete(temp_config) if File.exists?(temp_config)
        ENV.delete("TEST_VERBOSE")
      end
    end

    it "returns options normally when the print option is not in argv" do
      doc = "Usage: test [--verbose=<level>]"
      io = IO::Memory.new

      options = Docopt.docopt_config(doc, argv: ["--verbose", "1"],
        print_config_option: "--print-config", exit: false, io: io)

      io.to_s.should be_empty
      options["--verbose"].should eq("1")
    end

    it "treats the print option as an unknown option when not configured" do
      doc = "Usage: test [--verbose=<level>]"

      expect_raises(Docopt::DocoptExit) do
        Docopt.docopt_config(doc, argv: ["--print-config"], exit: false)
      end
    end
  end

  describe Docopt::ConfigOptions do
    it "resolves tiers in precedence order" do
      args = {"--verbose" => "cli"} of String => Docopt::DocoptValue?
      defaults = {"--verbose" => "default"} of String => Docopt::OptionValue?
      env = {"--verbose" => "env", "--output" => "out.txt"} of String => String
      config = config_from_yaml("verbose: config-value\nfont: cfg.ttf\n")

      options = Docopt::ConfigOptions.new(args, defaults, config, env)

      options["--verbose"].should eq("cli")    # CLI beats everything
      options["--output"].should eq("out.txt") # env when no CLI
      options["--font"].should eq("cfg.ttf")   # config when no CLI/env
    end

    it "falls back to docopt defaults when no other tier answers" do
      args = {"--force" => false} of String => Docopt::DocoptValue?
      defaults = {"--verbose" => "default"} of String => Docopt::OptionValue?

      options = Docopt::ConfigOptions.new(args, defaults)

      options["--force"].should be_nil # absent flag, no other source
      options["--verbose"].should eq("default")
      options.has_key?("--verbose").should be_true
    end

    it "accepts short option keys in config candidates" do
      args = {"-v" => 0} of String => Docopt::DocoptValue?
      config = config_from_yaml("v: 3\n")

      options = Docopt::ConfigOptions.new(args, Hash(String, Docopt::OptionValue?).new, config)

      options["-v"].should eq(3)
      options.has_key?("-v").should be_true
    end

    it "serializes the effective configuration as snake_case YAML" do
      args = {"--verbose" => nil, "--font" => ["cli.ttf"], "--force" => false} of String => Docopt::DocoptValue?
      defaults = {"--input-file" => "/data/default.csv"} of String => Docopt::OptionValue?
      env = {"--verbose" => "9"} of String => String
      config = config_from_yaml("font:\n  - one.ttf\n  - two.ttf\nforce: true\n")

      options = Docopt::ConfigOptions.new(args, defaults, config, env)

      yaml = YAML.parse(options.to_config_yaml)
      yaml["verbose"].should eq("9")
      yaml["font"].as_a.map(&.as_s).should eq(["cli.ttf"]) # CLI beats config
      yaml["force"].should be_true
      yaml["input_file"].should eq("/data/default.csv")
    end
  end
end

COMPILE_DOC = <<-DOC
  Tool.

  Usage:
    tool [-v] [--help] [--speed=<kn>] [--data=<d>...] <file>

  Options:
    -v            Verbose.
    --help        Show help.
    --speed=<kn>  Speed [default: 10].
    --data=<d>    Data [default: x].
  DOC

# Parsed while compiling this spec; a constant is the usual way to
# hand the usage text over
COMPILED_CONFIG = Docopt.compile_config(COMPILE_DOC)

describe "Docopt::ConfigCompiled" do
  it "gives the same results as parsing the doc per call" do
    argvs = [
      ["f.txt"],
      ["-v", "f.txt"],
      ["--speed=5", "f.txt"],
      ["--data=a", "--data=b", "f.txt"],
    ]
    argvs.each do |argv|
      via_pattern = Docopt.docopt_config(COMPILED_CONFIG, argv: argv, env_prefix: "TOOL", exit: false)
      via_doc = Docopt.docopt_config(COMPILE_DOC, argv: argv, env_prefix: "TOOL", exit: false)
      via_pattern["--speed"].should eq via_doc["--speed"]
      via_pattern["--data"].should eq via_doc["--data"]
      via_pattern["-v"].should eq via_doc["-v"]
      via_pattern["<file>"].should eq via_doc["<file>"]
    end
  end

  it "keeps the defaults tier from the same parse" do
    options = Docopt.docopt_config(COMPILED_CONFIG, argv: ["f.txt"], exit: false)
    options["--speed"].should eq 10
    options["--data"].should eq ["x"]
  end

  it "memoizes the defaults-stripped pattern" do
    pattern = Docopt::ConfigCompiled.parse(COMPILE_DOC)
    pattern.without_defaults.should be pattern.without_defaults
  end

  it "can be matched repeatedly without drifting" do
    argvs = [["f.txt"], ["-v", "--speed=1", "f.txt"], ["--data=q", "f.txt"]]
    argvs.each do |argv|
      first = Docopt.docopt_config(COMPILED_CONFIG, argv: argv, env_prefix: "DOCOPTCOMPILED", exit: false)
      second = Docopt.docopt_config(COMPILED_CONFIG, argv: argv, env_prefix: "DOCOPTCOMPILED", exit: false)
      # ConfigOptions has no ==; the drift concern is the parsed args
      second.args.should eq first.args
      second.docopt_defaults.should eq first.docopt_defaults
    end
  end

  it "honors the env tier through the compiled pattern" do
    ENV["TOOL_SPEED"] = "7"
    begin
      options = Docopt.docopt_config(COMPILED_CONFIG, argv: ["f.txt"], env_prefix: "TOOL", exit: false)
      options["--speed"].should eq "7"
    ensure
      ENV.delete("TOOL_SPEED")
    end
  end

  it "raises ConfigExit for help through the compiled pattern" do
    io = IO::Memory.new
    expect_raises(Docopt::ConfigExit) do
      Docopt.docopt_config(COMPILED_CONFIG, argv: ["--help", "f.txt"], exit: false, io: io)
    end
    io.to_s.should contain "Tool."
  end

  it "raises DocoptExit for unmatched argv through the compiled pattern" do
    io = IO::Memory.new
    expect_raises(Docopt::DocoptExit) do
      Docopt.docopt_config(COMPILED_CONFIG, argv: ["--nope"], exit: false, io: io)
    end
  end
end
