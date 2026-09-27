require "./spec_helper"
require "../src/docopt/dispatch"

struct EmpathyGreet < Docopt::Dispatch::Command
  @@name = "empathy-cmd"
  @@doc = <<-HELP
    Greets

    Usage:
      spec empathy-cmd [--verbose]

    Options:
      --verbose  Verbose
    HELP

  def run : Int32
    0
  end
end

EmpathyGreet.register

# Error empathy: failed matches explain what went wrong and suggest
# what the user probably meant, instead of dumping the usage alone.

EMPATHY_DOC = <<-DOC
  Prog.

  Usage:
    prog [--verbose] [--version]
    prog (add|remove) <file>

  Options:
    --verbose  Verbose
    --version  Version
  DOC

def empathy_message(argv : Array(String)) : String
  error = expect_raises(Docopt::DocoptExit) do
    Docopt.docopt(EMPATHY_DOC, argv, help: false, exit: false)
  end
  message = error.message
  message ? message : ""
end

describe "error messages" do
  it "suggest declared options for close unknown ones" do
    message = empathy_message(["--verbso"])
    message.should contain "Unknown option --verbso"
    message.should contain "Did you mean --verbose?"
  end

  it "do not suggest anything for far unknown options" do
    message = empathy_message(["--nonsense"])
    message.should contain "Unknown option --nonsense"
    message.should_not contain "Did you mean"
  end

  it "do not suggest against short tokens, where everything is close" do
    message = empathy_message(["-x"])
    message.should contain "Unknown option -x"
    message.should_not contain "Did you mean"
  end

  it "explain repeated flags over their allowed count" do
    doc = "Usage: prog [-vv]"
    error = expect_raises(Docopt::DocoptExit) do
      Docopt.docopt(doc, ["-vvv"], help: false, exit: false)
    end
    message = error.message.to_s
    message.should contain "too many times"
    message.should contain "-v"
  end

  it "suggest declared commands for close unexpected arguments" do
    message = empathy_message(["ad", "f.txt"])
    message.should contain "Unexpected argument 'ad'"
    message.should contain "Did you mean 'add'?"
  end

  it "say nothing extra for unrelated arguments" do
    message = empathy_message(["xyzzy", "f.txt"])
    message.should contain "Unexpected argument 'xyzzy'"
    message.should_not contain "Did you mean"
  end

  it "keep the prefix-ambiguity message listing its candidates" do
    message = empathy_message(["--ver"])
    message.should contain "not a uniq prefix"
    message.should contain "--verbose"
    message.should contain "--version"
  end

  it "surface the message when dispatching, before the usage" do
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    code = Docopt::Dispatch.main("spec", ["empathy-cmd", "--verbso"], stdout: stdout_io, stderr: stderr_io)
    code.should eq 1
    stderr_io.to_s.should contain "Unknown option --verbso"
    stderr_io.to_s.should contain "Usage:"
  end
end

describe "Docopt.suggestions_for" do
  it "is available from the core, domain independent" do
    Docopt.suggestions_for("--verbso", ["--verbose", "--version", "-v"]).should eq ["--verbose"]
    Docopt.levenshtein_distance("Add", "add").should eq 0
  end
end
