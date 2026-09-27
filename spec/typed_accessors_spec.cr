require "./spec_helper"
require "../src/docopt/config"
require "../src/docopt/dispatch"

# Typed access over option values: ask for the type, get either the
# value or a message naming the option, the value and its type.

TYPED_DOC = <<-DOC
  Typed.

  Usage:
    typed [-v | -vv] [--speed=<kn>] <name>...

  Options:
    --speed=<kn>  Speed [default: 10].
  DOC

TYPED_CONFIG_DOC = <<-DOC
  Typed.

  Usage:
    typed [--speed=<kn>] [--ratio=<r>] <name>

  Options:
    --speed=<kn>  Speed [default: 10].
    --ratio=<r>   Ratio [default: 1].
  DOC

struct TypedGreet < Docopt::Dispatch::Command
  @@name = "typed-cmd"
  @@doc = <<-HELP
    Greets

    Usage:
      spec typed-cmd [--shout]

    Options:
      --shout  Shout it
    HELP

  class_property shouted : Bool?

  def run : Int32
    @@shouted = options.bool("--shout")
    0
  end
end

TypedGreet.register

def typed_options(argv : Array(String)) : Docopt::Result
  Docopt.docopt(TYPED_DOC, argv, help: false, exit: false)
end

describe "typed accessors" do
  it "hand out strings, ints, bools and arrays" do
    options = typed_options(["-vv", "--speed=3", "a", "b"])
    options.string("--speed").should eq "3"
    options.int("-v").should eq 2
    options.array("<name>").should eq ["a", "b"]
    typed_options(["-v", "a"]).int("-v").should eq 1
  end

  it "default to nil for absent values in the ? variants" do
    options = typed_options(["a"])
    options.string?("--speed").should eq "10" # the declared default
    options.string?("--nope").should be_nil
    options.array?("<name>").should eq ["a"]
    options.int?("-v").should eq 0 # counting flags are integers
    options.bool?("--nope").should be_nil
  end

  it "name the option and its actual type on a wrong ask" do
    options = typed_options(["--speed=3", "a"])
    error = expect_raises(Docopt::TypeMismatchError) do
      options.int("--speed")
    end
    error.message.to_s.should contain "--speed"
    error.message.to_s.should contain "3"
    error.message.to_s.should contain "String"
  end

  it "say an option was not given when absent" do
    options = typed_options(["a"])
    error = expect_raises(Docopt::TypeMismatchError) do
      options.string("--nope")
    end
    error.message.to_s.should contain "--nope was not given"
  end

  it "answer through ConfigOptions, after precedence" do
    ENV["TYPED_SPEED"] = "7"
    Dir.tempdir.tap do |dir|
      config = File.join(dir, "docopt-typed-#{Random::Secure.hex(4)}.yml")
      File.write(config, "ratio: 0.5\n")
      begin
        options = Docopt.docopt_config(TYPED_CONFIG_DOC,
          argv: ["a"], config_file_path: config, env_prefix: "TYPED", exit: false)
        options.string("--speed").should eq "7"
        options.float("--ratio").should eq 0.5
      ensure
        ENV.delete("TYPED_SPEED")
        File.delete(config)
      end
    end
  end

  it "work inside dispatch commands" do
    Docopt::Dispatch.main("spec", ["typed-cmd", "--shout"],
      stdout: IO::Memory.new, stderr: IO::Memory.new)
    TypedGreet.shouted.should be_true
  end
end
