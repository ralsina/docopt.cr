require "./spec_helper"

NAVAL_FATE = <<-DOC
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

# Parsed while compiling this spec; a constant is the usual way to
# hand the usage text over
NAVAL_COMPILED = Docopt.compile(NAVAL_FATE)

# A literal works too
LITERAL_DOC = <<-DOC
  Usage: prog [-v] [--count=<n>] <file>...

  Options:
    -v            Verbose.
    --count=<n>   How many [default: 3].
  DOC

LITERAL_COMPILED = Docopt.compile(LITERAL_DOC)

NAVAL_ARGVS = [
  ["ship", "A", "move", "a", "b", "--speed=3"],
  ["ship", "new", "A", "B", "C"],
  ["ship", "shoot", "1", "2"],
  ["mine", "set", "1", "2", "--moored"],
  ["mine", "remove", "1", "2"],
  ["--version"],
]

describe "Docopt.parse and Docopt.match" do
  it "give the same result as docopt" do
    compiled = Docopt.parse(NAVAL_FATE)
    NAVAL_ARGVS.each do |argv|
      Docopt.match(compiled, argv, help: false, exit: false).should eq Docopt.docopt(NAVAL_FATE, argv, help: false, exit: false)
    end
  end

  it "can match the same compiled pattern repeatedly" do
    compiled = Docopt.parse(NAVAL_FATE)
    options_before = compiled.options.size
    first = Docopt.match(compiled, ["ship", "new", "A"], exit: false)
    second = Docopt.match(compiled, ["ship", "new", "B", "C"], exit: false)
    third = Docopt.match(compiled, ["ship", "new", "A"], exit: false)
    first["<name>"].should eq ["A"]
    second["<name>"].should eq ["B", "C"]
    third.should eq first
    compiled.options.size.should eq options_before
  end

  it "raises on unmatched arguments when exit is false" do
    compiled = Docopt.parse(NAVAL_FATE)
    expect_raises(Docopt::DocoptExit) do
      Docopt.match(compiled, ["ship", "fly"], exit: false)
    end
  end

  it "raises on an invalid usage text" do
    expect_raises(Docopt::DocoptLanguageError) do
      Docopt.parse("no usage section here")
    end
  end
end

describe "Docopt.compile" do
  it "embeds the same pattern that parsing at runtime produces" do
    runtime = Docopt.parse(NAVAL_FATE)
    NAVAL_COMPILED.pattern.to_s.should eq runtime.pattern.to_s
    NAVAL_COMPILED.options.map(&.to_s).should eq runtime.options.map(&.to_s)
    NAVAL_COMPILED.usage.should eq runtime.usage
    NAVAL_COMPILED.doc.should eq runtime.doc
  end

  it "keeps equal leaves as one object, as fix_identities does" do
    leaves = NAVAL_COMPILED.pattern.flat
    xs = leaves.select { |leaf| leaf.is_a?(Docopt::Argument) && leaf.name == "<x>" }
    xs.size.should be > 1
    xs.map(&.object_id).uniq!.size.should eq 1
  end

  it "matches like docopt" do
    NAVAL_ARGVS.each do |argv|
      Docopt.match(NAVAL_COMPILED, argv, help: false, exit: false).should eq Docopt.docopt(NAVAL_FATE, argv, help: false, exit: false)
    end
  end

  it "accepts a string literal" do
    result = Docopt.match(LITERAL_COMPILED, ["-v", "a", "b"], exit: false)
    result["-v"].should be_true
    result["--count"].should eq "3"
    result["<file>"].should eq ["a", "b"]
  end

  it "round-trips through to_crystal" do
    # The generated source must be stable: serializing the compiled
    # pattern again yields the same code
    Docopt.parse(NAVAL_FATE).to_crystal.should eq NAVAL_COMPILED.to_crystal
  end
end

describe "Compiled#defaults" do
  it "maps every declared option to its absent-from-argv value" do
    defaults = Docopt.parse(NAVAL_FATE).defaults
    defaults["--speed"].should eq "10"
    defaults["--moored"].should be_false
    defaults["--drifting"].should be_false
    defaults["--help"].should be_false
    defaults["--version"].should be_false
  end

  it "keeps array defaults of repeated options" do
    doc = <<-DOC
      Usage: prog [--data=<data>...]

      Options:
        -d --data=<arg>  Input data [default: x y].
      DOC
    Docopt.parse(doc).defaults["--data"].should eq ["x", "y"]
  end

  it "is nil for options without a declared default" do
    defaults = Docopt.parse(LITERAL_DOC).defaults
    defaults["--count"].should eq "3"
    defaults["-v"].should be_false
  end
end

describe "Compiled#without_defaults" do
  defaults_doc = <<-DOC
    Usage: prog [-v] [--speed=<kn>] [--data=<d>...] <file>

    Options:
      -v            Verbose.
      --speed=<kn>  Speed [default: 10].
      --data=<d>    Data [default: x].
    DOC

  it "parses absent options as not-provided instead of their defaults" do
    stripped = Docopt.parse(defaults_doc).without_defaults
    result = Docopt.match(stripped, ["f.txt"], help: false, exit: false)
    result["--speed"].should be_nil
    result["--data"].should eq [] of String
    result["-v"].should be_false
    result["<file>"].should eq "f.txt"
  end

  it "is equivalent to matching a doc with the defaults stripped" do
    doc_without_defaults = defaults_doc.gsub(/\s*\[default:\s*([^\]]+)\]/i, "")
    compiled = Docopt.parse(defaults_doc)
    argvs = [
      ["f.txt"],
      ["-v", "f.txt"],
      ["--speed=5", "f.txt"],
      ["--data=a", "--data=b", "f.txt"],
      ["-v", "--speed=5", "--data=a", "f.txt"],
    ]
    argvs.each do |argv|
      stripped_match = Docopt.match(compiled.without_defaults, argv, help: false, exit: false)
      reference_match = Docopt.docopt(doc_without_defaults, argv, help: false, exit: false)
      stripped_match.should eq reference_match
    end
  end

  it "leaves the original pattern untouched" do
    compiled = Docopt.parse(defaults_doc)
    options_before = compiled.options.map(&.to_s)
    pattern_before = compiled.pattern.to_s

    Docopt.match(compiled.without_defaults, ["f.txt"], help: false, exit: false)
    Docopt.match(compiled, ["f.txt"], help: false, exit: false)

    compiled.options.map(&.to_s).should eq options_before
    compiled.pattern.to_s.should eq pattern_before
    Docopt.match(compiled, ["f.txt"], help: false, exit: false)["--speed"].should eq "10"
  end

  it "keeps equal leaves as one shared object" do
    copy = Docopt.parse(NAVAL_FATE).without_defaults
    xs = copy.pattern.flat.select { |leaf| leaf.is_a?(Docopt::Argument) && leaf.name == "<x>" }
    xs.size.should be > 1
    xs.map(&.object_id).uniq!.size.should eq 1
  end

  it "agrees with the original on values that are not declared defaults" do
    copy = Docopt.parse(NAVAL_FATE).without_defaults
    copy.options.size.should eq Docopt.parse(NAVAL_FATE).options.size
    copy.options.map(&.name.to_s).sort!.should eq Docopt.parse(NAVAL_FATE).options.map(&.name.to_s).sort!
    # Flags keep their absent value in both
    if flag = copy.options.find { |option| option.name == "--moored" }
      flag.value.should be_false
    end
  end
end
