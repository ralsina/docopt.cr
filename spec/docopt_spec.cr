require "./spec_helper"

describe "Docopt" do
  # TODO: Write tests

  full_doc = <<-DOC
  Naval Fate.

  Usage:
    naval_fate init [-v]...
    naval_fate ship new <name>...
    naval_fate ship <name> move <x> <y> [--speed=<kn>]
    naval_fate ship shoot <x> <y>
    naval_fate mine (set|remove) <x> <y> [--moored|--drifting]
    naval_fate save [--files=files...]
    naval_fate set_speed [--speed=<kn>]
    naval_fate -h | --help
    naval_fate --version

  Options:
    -h --help        Show this screen.
    --version        Show version.
    -s,--speed=<kn>  Speed in knots [default: 10].
    --moored         Moored (anchored) mine.
    --drifting       Drifting mine.
  DOC

  # Test helper
  process = ->(argv : Array(String)) {
    Docopt.docopt(full_doc, argv, help: false, exit: false)
  }

  it "should match with subcommands and options" do
    std = {"ship" => true, "new" => false, "<name>" => ["A"], "move" => true, "<x>" => "a", "<y>" => "b", "--speed" => "3", "shoot" => false, "mine" => false, "set" => false, "remove" => false, "--moored" => nil, "--drifting" => nil, "-h" => nil, "--help" => nil, "--version" => nil}
    ans = process.call(["ship", "A", "move", "a", "b", "--speed=3"])
    std.each do |key, value|
      ans[key]?.should eq(value), "the key #{key} does not match the expected"
    end
  end

  it "should support repeat options" do
    # With value
    ans = process.call(["save", "--files=a.txt", "--files=b.txt"])
    farr = ans["--files"] as Array(String)
    "a.txt".should eq(farr[0])
    "b.txt".should eq(farr[1])

    # Only repeat
    ans = process.call(["init", "-vv"])
    ans["init"].should be_true
    ans["-v"].should eq(2)
  end

  it("should support alias options with default value") do
    ans = process.call(["set_speed"])
    ans["set_speed"].should be_true
    ans["--speed"].should eq("10")
    ans = process.call(["set_speed", "--speed", "20"])
    ans["--speed"].should eq("20")
    ans = process.call(["-h"])
    ans["--help"].should be_true
  end
end
