require "./spec_helper"

describe Docopt do
  # TODO: Write tests

  it "works" do
    doc = <<-DOC
Naval Fate.

Usage:
  naval_fate ship new <name>...
  naval_fate ship <name> move <x> <y> [--speed=<kn>]
  naval_fate ship shoot <x> <y>
  naval_fate mine (set|remove) <x> <y> [--moored|--drifting]
  naval_fate -h | --help
  naval_fate --version

Options:
  -h --help     Show this screen.
  --version     Show version.
  --speed=<kn>  Speed in knots [default: 10].
  --moored      Moored (anchored) mine.
  --drifting    Drifting mine.
DOC
    std = {"ship" => true, "new" => false, "<name>" => "A", "move" => true, "<x>" => "a", "<y>" => "b", "--speed" => "3", "shoot" => false, "mine" => false, "set" => false, "remove" => false, "--moored" => nil, "--drifting" => nil, "-h" => nil, "--help" => false, "--version" => nil}
    # ans = Docopt.docopt(doc, argv = ["ship", "A", "mov", "a", "b", "--speed=3"])
    # ans.shoud eq(std)
  end
end
