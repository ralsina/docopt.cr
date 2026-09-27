require "./spec_helper"

# The -Dcolor_docopt fallback: zero-code colored help when tartrazine
# is among the dependencies. Compiled only under the flag, so the
# suite runs it through: crystal spec -Dcolor_docopt spec/color_flag_spec.cr
{% if flag?(:color_docopt) %}
  describe "color_docopt flag" do
    it "colors through tartrazine without any explicit setup" do
      colored = Docopt.colorize("Usage:\n  prog [-v]\n", TTYMemory.new)
      colored.should contain "\e["
      colored.should contain "Usage"
    end

    it "keeps the gates: plain off-terminal" do
      Docopt.colorize("Usage:\n  prog [-v]\n", IO::Memory.new)
        .should eq "Usage:\n  prog [-v]\n"
    end

    it "an explicit colorizer wins over the fallback" do
      Docopt.colorizer = ->(text : String) { "<x>#{text}</x>" }
      begin
        Docopt.colorize("Usage:", TTYMemory.new).should eq "<x>Usage:</x>"
      ensure
        Docopt.colorizer = nil
      end
    end
  end
{% end %}
