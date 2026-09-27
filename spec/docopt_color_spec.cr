require "./spec_helper"
require "../src/docopt/color"

# The tartrazine-backed colorizer: docopt's own lexer highlights help
# text, in-process (no external tool).

describe "Docopt.use_tartrazine_color" do
  it "colorizes through the docopt lexer on a terminal" do
    Docopt.use_tartrazine_color
    begin
      colored = Docopt.colorize("Usage:\n  prog [-v]\n", TTYMemory.new)
      colored.should contain "\e["
      colored.should contain "Usage" # escapes interleave inside words
    ensure
      Docopt.colorizer = nil
    end
  end

  it "accepts any tartrazine theme" do
    Docopt.use_tartrazine_color("pastie")
    begin
      colored = Docopt.colorize("Usage:\n  prog [-v]\n", TTYMemory.new)
      colored.should contain "\e["
    ensure
      Docopt.colorizer = nil
    end
  end

  it "stays plain off-terminal and under NO_COLOR" do
    Docopt.use_tartrazine_color
    begin
      text = "Usage:\n  prog [-v]\n"
      Docopt.colorize(text, IO::Memory.new).should eq text
      ENV["NO_COLOR"] = "1"
      Docopt.colorize(text, TTYMemory.new).should eq text
    ensure
      ENV.delete("NO_COLOR")
      Docopt.colorizer = nil
    end
  end
end
