require "./spec_helper"
require "../src/docopt/dispatch"

struct SpecGreet < Docopt::Dispatch::Command
  @@name = "greet"
  @@doc = <<-HELP
    Greets people

    Usage:
      spec greet [-u] [-p PLANET]

    Options:
      -h --help     Show this screen
      -u --upper    Uppercase output
      -p PLANET     Planet to greet [default: world]
    HELP

  class_property? executed = false
  class_property last_planet : String = ""

  def run : Int32
    @@executed = true
    @@last_planet = options.fetch("-p", "").as?(String) || ""
    0
  end
end

struct SpecFail < Docopt::Dispatch::Command
  @@name = "fail"
  @@doc = <<-HELP
    Always fails

    Usage:
      spec fail
    HELP

  def run : Int32
    7
  end
end

struct SpecGreat < Docopt::Dispatch::Command
  @@name = "great"
  @@doc = <<-HELP
    Greets greatly

    Usage:
      spec great
    HELP

  def run : Int32
    0
  end
end

SpecGreet.register
SpecFail.register
SpecGreat.register

struct SpecBroken < Docopt::Dispatch::Command
  @@name = "broken-spec-cmd"
  @@doc = <<-HELP
    No usage here at all.
    HELP

  def run : Int32
    0
  end
end

def run_main(arguments : Array(String))
  stdout_io = IO::Memory.new
  stderr_io = IO::Memory.new
  code = Docopt::Dispatch.main("spec", arguments, stdout: stdout_io, stderr: stderr_io)
  {code, stdout_io.to_s, stderr_io.to_s}
end

describe Docopt::Dispatch do
  describe ".levenshtein_distance" do
    it "is zero for identical strings" do
      Docopt::Dispatch.levenshtein_distance("greet", "greet").should eq(0)
    end

    it "ignores case" do
      Docopt::Dispatch.levenshtein_distance("Greet", "GREET").should eq(0)
    end

    it "measures single character edits" do
      Docopt::Dispatch.levenshtein_distance("hello", "helllo").should eq(1)
      Docopt::Dispatch.levenshtein_distance("grret", "greet").should eq(1)
      Docopt::Dispatch.levenshtein_distance("kitten", "sitting").should eq(3)
    end

    it "handles empty strings" do
      Docopt::Dispatch.levenshtein_distance("", "abc").should eq(3)
      Docopt::Dispatch.levenshtein_distance("", "").should eq(0)
    end
  end

  describe ".suggestions_for" do
    it "suggests close registered commands" do
      Docopt::Dispatch.suggestions_for("failr").should eq(["fail"])
    end

    it "breaks distance ties alphabetically" do
      Docopt::Dispatch.suggestions_for("gret").should eq(["great", "greet", "cgreet"])
    end

    it "suggests nothing when nothing is close enough" do
      Docopt::Dispatch.suggestions_for("zzzzzzzzzz").should eq([] of String)
    end

    it "works on any candidate list" do
      options = ["--verbose", "--version", "--force"]
      Docopt::Dispatch.suggestions_for("--verbos", options).should eq(["--verbose"])
    end

    it "caps the list at four suggestions" do
      candidates = ["aa", "ab", "ac", "ad", "ae", "af"]
      Docopt::Dispatch.suggestions_for("ag", candidates).should eq(["aa", "ab", "ac", "ad"])
    end
  end

  describe ".main" do
    it "runs a registered command and returns its exit code" do
      code, _stdout, stderr = run_main(["greet", "-p", "mars"])
      code.should eq(0)
      SpecGreet.executed?.should be_true
      SpecGreet.last_planet.should eq("mars")
      stderr.should be_empty
    end

    it "propagates non-zero exit codes from commands" do
      code, _stdout, _stderr = run_main(["fail"])
      code.should eq(7)
    end

    context "with no arguments" do
      it "prints top level help" do
        code, stdout, stderr = run_main([] of String)
        code.should eq(0)
        stdout.should contain("Usage:")
        stdout.should contain("spec help [COMMAND]")
        stdout.should contain("Commands:")
        stdout.should contain("Greets people")
        stdout.should contain("Greets greatly")
        stderr.should be_empty
      end
    end

    context "with --help or -h" do
      it "prints top level help" do
        code, stdout, _stderr = run_main(["--help"])
        code.should eq(0)
        stdout.should contain("Commands:")
      end

      it "prints top level help for -h" do
        code, stdout, _stderr = run_main(["-h"])
        code.should eq(0)
        stdout.should contain("Commands:")
      end
    end

    context "with the help command" do
      it "prints top level help without an argument" do
        code, stdout, _stderr = run_main(["help"])
        code.should eq(0)
        stdout.should contain("Commands:")
      end

      it "prints a command's documentation" do
        code, stdout, _stderr = run_main(["help", "greet"])
        code.should eq(0)
        stdout.should contain("Greets people")
        stdout.should contain("-p PLANET")
      end

      it "fails with suggestions for unknown commands" do
        code, _stdout, stderr = run_main(["help", "greot"])
        code.should eq(1)
        stderr.should contain("is not a spec command")
        stderr.should contain("The most similar commands are")
        stderr.should contain("greet")
        stderr.should contain("great")
      end

      it "rejects extra arguments" do
        code, _stdout, stderr = run_main(["help", "greet", "extra"])
        code.should eq(1)
        stderr.should contain("Usage:")
      end
    end

    context "with an unknown command" do
      it "suggests similar commands like git" do
        code, _stdout, stderr = run_main(["fial"])
        code.should eq(1)
        stderr.should contain("'fial' is not a spec command")
        stderr.should contain("The most similar command is")
        stderr.should contain("\tfail")
      end

      it "prints no suggestions when nothing is similar" do
        code, _stdout, stderr = run_main(["zzzzzzz"])
        code.should eq(1)
        stderr.should contain("is not a spec command")
        stderr.should_not contain("most similar")
      end
    end

    context "with invalid arguments for a known command" do
      it "prints usage and a hint to stderr" do
        code, _stdout, stderr = run_main(["greet", "-x"])
        code.should eq(1)
        stderr.should contain("Usage:")
        stderr.should contain("See 'spec help greet'")
      end
    end

    context "with help flags after the -- separator" do
      it "treats them as arguments, not help requests" do
        code, stdout, stderr = run_main(["greet", "--", "--help"])
        code.should eq(1)
        stdout.should be_empty
        stderr.should contain("Usage:")
      end

      it "treats -h after -- the same way" do
        code, _stdout, stderr = run_main(["greet", "--", "-h"])
        code.should eq(1)
        stderr.should contain("Usage:")
      end
    end

    it "parses each command once, reusing the compiled pattern" do
      SpecGreet.compiled.should be SpecGreet.compiled
      first_code, _stdout, _stderr = run_main(["greet", "-p", "mars"])
      second_code, _stdout, _stderr = run_main(["greet", "-p", "mars"])
      first_code.should eq(0)
      second_code.should eq(0)
      SpecGreet.last_planet.should eq("mars")
      # matching did not grow or alter the cached pattern
      SpecGreet.compiled.options.size.should be > 0
    end

    context "with --help on a known command" do
      it "prints that command's documentation" do
        code, stdout, stderr = run_main(["greet", "--help"])
        code.should eq(0)
        stdout.should contain("Greets people")
        stdout.should contain("-p PLANET")
        stderr.should be_empty
      end
    end
  end

  describe Docopt::Dispatch::Command do
    it "rejects documentation without a usage section" do
      expect_raises(ArgumentError, "no 'Usage:' section") do
        SpecBroken.register
      end
    end

    it "rejects duplicate command names" do
      expect_raises(ArgumentError, "already registered") do
        SpecGreet.register
      end
    end
  end
end

describe "Docopt::Dispatch completions" do
  it "grafts every registered command under one root" do
    tree, _option_help = Docopt::Dispatch.completion_params
    tree.subcommands.keys.should contain "greet"
    tree.subcommands.keys.should contain "fail"
    tree.subcommands.keys.should contain "great"
    # the built-in help command completes too
    tree.subcommands.keys.should contain "help"
    greet_words = tree.subcommands["greet"].option_specs.flat_map(&.words)
    greet_words.should contain "--upper"
    greet_words.should contain "-p="
  end

  it "generates a bash script completing command names and options" do
    with_completion_workdir do |dir|
      script = File.join(dir, "spec.sh")
      File.write(script, Docopt::Dispatch.bash_completion("spec"))

      replies, error = bash_complete(script, "_spec", [""])
      # every spec file may register commands into the shared registry
      replies.should contain "greet"
      replies.should contain "fail"
      replies.should contain "great"
      replies.should contain "help"
      error.should_not contain("command not found")

      replies, _error = bash_complete(script, "_spec", ["gr"])
      replies.should eq ["greet", "great"]

      replies, _error = bash_complete(script, "_spec", ["greet", ""])
      replies.should contain "--upper"
      replies.should contain "-p="
    end
  end

  it "applies custom completions per command path" do
    with_completion_workdir do |dir|
      script = File.join(dir, "spec.sh")
      File.write(script, Docopt::Dispatch.bash_completion("spec", {"spec_greet" => "mars venus"}))
      replies, _error = bash_complete(script, "_spec", ["greet", ""])
      replies.should eq ["mars", "venus"]
    end
  end

  if shell_available?("fish") && shell_available?("zsh")
    it "generates valid fish and zsh scripts" do
      with_completion_workdir do |dir|
        fish_script = File.join(dir, "spec.fish")
        zsh_script = File.join(dir, "_spec")
        File.write(fish_script, Docopt::Dispatch.fish_completion("spec"))
        File.write(zsh_script, Docopt::Dispatch.zsh_completion("spec"))

        status, _output, error = run_shell("fish", ["--no-execute", fish_script])
        status.should eq 0
        error.should be_empty
        status, _output, error = run_shell("zsh", ["-n", zsh_script])
        status.should eq 0
        error.should be_empty

        words = fish_complete(fish_script, "spec ")
        words.should contain "greet"
        words.should contain "help"
      end
    end
  end
end
