require "./spec_helper"
require "../src/docopt/config"
require "../src/docopt/dispatch"

struct ColorCmd < Docopt::Dispatch::Command
  @@name = "color-cmd"
  @@doc = "Colorful.\n\nUsage:\n  spec color-cmd [-v]\n\nOptions:\n  -v  Verbose.\n"

  def run : Int32
    0
  end
end

ColorCmd.register

# The colorizer hook: Docopt.colorizer= installs a proc that colors
# help and usage text, applied only on terminals without NO_COLOR.

class TTYMemory < IO::Memory
  def tty? : Bool
    true
  end
end

COLOR_DOC = "Usage:\n  prog [-v] [-h | --help]\n\nOptions:\n  -v  Verbose.\n  -h --help  Show help.\n"

def with_fake_colorizer(&) : Nil
  Docopt.colorizer = ->(text : String) { "<c>#{text}</c>" }
  begin
    yield
  ensure
    Docopt.colorizer = nil
  end
end

describe "colored output" do
  it "applies the colorizer on a terminal" do
    with_fake_colorizer do
      Docopt.colorize(COLOR_DOC, TTYMemory.new).should start_with "<c>Usage:"
    end
  end

  it "leaves non-terminals plain" do
    with_fake_colorizer do
      Docopt.colorize(COLOR_DOC, IO::Memory.new).should start_with "Usage:"
    end
  end

  it "respects NO_COLOR" do
    ENV["NO_COLOR"] = "1"
    with_fake_colorizer do
      Docopt.colorize(COLOR_DOC, TTYMemory.new).should start_with "Usage:"
    end
  ensure
    ENV.delete("NO_COLOR")
  end

  it "is plain without a colorizer" do
    Docopt.colorize(COLOR_DOC, TTYMemory.new).should eq COLOR_DOC
  end

  it "colors help through the config layer" do
    with_fake_colorizer do
      io = TTYMemory.new
      Docopt.docopt_config(COLOR_DOC, argv: ["--help"], exit: false, io: io) rescue nil
      io.to_s.should start_with "<c>Usage:"
    end
  end

  it "colors help through dispatch" do
    with_fake_colorizer do
      io = TTYMemory.new
      Docopt::Dispatch.main("spec", ["color-cmd", "--help"], stdout: io, stderr: IO::Memory.new)
      io.to_s.should start_with "<c>"
    end
  end
end
