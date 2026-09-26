# Unit tests ported from the reference implementation's test suite:
#
#   https://github.com/docopt/docopt/blob/master/test_docopt.py
#
# They complement the conformance suite with behaviors testcases.docopt
# does not cover: language errors for malformed docs, error precedence,
# pattern-matching internals and section parsing.

require "./spec_helper"

def docopt_for(doc : String, argv : String)
  Docopt.docopt(doc, argv.split, help: false, exit: false)
end

describe "reference: Option.parse" do
  it "parses short and long names" do
    Docopt::Option.parse("-h").should eq Docopt::Option.new("-h", nil)
    Docopt::Option.parse("--help").should eq Docopt::Option.new(nil, "--help")
    Docopt::Option.parse("-h --help").should eq Docopt::Option.new("-h", "--help")
    Docopt::Option.parse("-h, --help").should eq Docopt::Option.new("-h", "--help")
  end

  it "parses arguments" do
    Docopt::Option.parse("-h TOPIC").should eq Docopt::Option.new("-h", nil, 1)
    Docopt::Option.parse("--help TOPIC").should eq Docopt::Option.new(nil, "--help", 1)
    Docopt::Option.parse("-h TOPIC --help TOPIC").should eq Docopt::Option.new("-h", "--help", 1)
    Docopt::Option.parse("-h TOPIC, --help TOPIC").should eq Docopt::Option.new("-h", "--help", 1)
    Docopt::Option.parse("-h TOPIC, --help=TOPIC").should eq Docopt::Option.new("-h", "--help", 1)
  end

  it "separates descriptions" do
    Docopt::Option.parse("-h  Description...").should eq Docopt::Option.new("-h", nil)
    Docopt::Option.parse("-h --help  Description...").should eq Docopt::Option.new("-h", "--help")
    Docopt::Option.parse("-h TOPIC  Description...").should eq Docopt::Option.new("-h", nil, 1)
    Docopt::Option.parse("    -h").should eq Docopt::Option.new("-h", nil)
  end

  it "parses defaults" do
    Docopt::Option.parse("-h TOPIC  Descripton... [default: 2]").should eq Docopt::Option.new("-h", nil, 1, "2")
    Docopt::Option.parse("-h TOPIC  Descripton... [default: topic-1]").should eq Docopt::Option.new("-h", nil, 1, "topic-1")
    Docopt::Option.parse("--help=TOPIC  ... [default: 3.14]").should eq Docopt::Option.new(nil, "--help", 1, "3.14")
    Docopt::Option.parse("-h, --help=DIR  ... [default: ./]").should eq Docopt::Option.new("-h", "--help", 1, "./")
    Docopt::Option.parse("-h TOPIC  Descripton... [dEfAuLt: 2]").should eq Docopt::Option.new("-h", nil, 1, "2")
  end

  it "names options after the long form when present" do
    Docopt::Option.new("-h", nil).name.should eq "-h"
    Docopt::Option.new("-h", "--help").name.should eq "--help"
    Docopt::Option.new(nil, "--help").name.should eq "--help"
  end
end

describe "reference: commands" do
  it "matches commands" do
    docopt_for("Usage: prog add", "add").should eq({"add" => true})
    docopt_for("Usage: prog [add]", "").should eq({"add" => false})
    docopt_for("Usage: prog [add]", "add").should eq({"add" => true})
    docopt_for("Usage: prog (add|rm)", "add").should eq({"add" => true, "rm" => false})
    docopt_for("Usage: prog (add|rm)", "rm").should eq({"add" => false, "rm" => true})
    docopt_for("Usage: prog a b", "a b").should eq({"a" => true, "b" => true})
    expect_raises(Docopt::DocoptExit) { docopt_for("Usage: prog a b", "b a") }
  end
end

describe "reference: error handling" do
  it "raises DocoptExit for unknown long options" do
    expect_raises(Docopt::DocoptExit) { docopt_for("Usage: prog", "--non-existent") }
    expect_raises(Docopt::DocoptExit) do
      docopt_for("Usage: prog [--version --verbose]\nOptions: --version\n --verbose", "--ver")
    end
    expect_raises(Docopt::DocoptExit) do
      docopt_for("Usage: prog --long ARG\nOptions: --long ARG", "--long")
    end
    expect_raises(Docopt::DocoptExit) do
      docopt_for("Usage: prog --long\nOptions: --long", "--long=ARG")
    end
  end

  it "raises DocoptLanguageError for malformed long options" do
    expect_raises(Docopt::DocoptLanguageError) do
      docopt_for("Usage: prog --long\nOptions: --long ARG", "")
    end
    expect_raises(Docopt::DocoptLanguageError) do
      docopt_for("Usage: prog --long=ARG\nOptions: --long", "")
    end
  end

  it "raises DocoptExit for unknown short options" do
    expect_raises(Docopt::DocoptExit) { docopt_for("Usage: prog", "-x") }
    expect_raises(Docopt::DocoptExit) do
      docopt_for("Usage: prog -o ARG\nOptions: -o ARG", "-o")
    end
  end

  it "raises DocoptLanguageError for ambiguous or malformed short options" do
    expect_raises(Docopt::DocoptLanguageError) do
      docopt_for("Usage: prog -x\nOptions: -x  this\n -x  that", "")
    end
    expect_raises(Docopt::DocoptLanguageError) do
      docopt_for("Usage: prog -o\nOptions: -o ARG", "")
    end
  end

  it "raises DocoptLanguageError for unmatched parens and brackets" do
    expect_raises(Docopt::DocoptLanguageError) { docopt_for("Usage: prog [a [b]", "") }
    expect_raises(Docopt::DocoptLanguageError) { docopt_for("Usage: prog [a [b] ] c )", "") }
  end

  it "raises DocoptLanguageError for missing or repeated usage sections" do
    expect_raises(Docopt::DocoptLanguageError) { docopt_for("no usage with colon here", "") }
    expect_raises(Docopt::DocoptLanguageError) { docopt_for("usage: here \n\n and again usage: here", "") }
  end
end

describe "reference: double dash" do
  it "treats -- after which everything is positional" do
    docopt_for("usage: prog [-o] [--] <arg>\nkptions: -o", "-- -o")
      .should eq({"-o" => false, "<arg>" => "-o", "--" => true})
    docopt_for("usage: prog [-o] [--] <arg>\nkptions: -o", "-o 1")
      .should eq({"-o" => true, "<arg>" => "1", "--" => false})
    expect_raises(Docopt::DocoptExit) { docopt_for("usage: prog [-o] <arg>\noptions:-o", "-- -o") }
  end
end

describe "reference: counting flags" do
  it "counts repeated flags" do
    docopt_for("usage: prog [-v]", "-v").should eq({"-v" => true})
    docopt_for("usage: prog [-vv]", "").should eq({"-v" => 0})
    docopt_for("usage: prog [-vv]", "-v").should eq({"-v" => 1})
    docopt_for("usage: prog [-vv]", "-vv").should eq({"-v" => 2})
    expect_raises(Docopt::DocoptExit) { docopt_for("usage: prog [-vv]", "-vvv") }
    docopt_for("usage: prog [-v | -vv | -vvv]", "-vvv").should eq({"-v" => 3})
    docopt_for("usage: prog -v...", "-vvvvvv").should eq({"-v" => 6})
    docopt_for("usage: prog [--ver --ver]", "--ver --ver").should eq({"--ver" => 2})
  end
end

describe "reference: defaults for repeatable options" do
  it "splits default values on whitespace" do
    doc = "Usage: prog [--data=<data>...]\n\nOptions:\n\t-d --data=<arg>    Input data [default: x]\n"
    docopt_for(doc, "").should eq({"--data" => ["x"]})
    doc = "Usage: prog [--data=<data>...]\n\nOptions:\n\t-d --data=<arg>    Input data [default: x y]\n"
    docopt_for(doc, "").should eq({"--data" => ["x", "y"]})
    docopt_for(doc, "--data=this").should eq({"--data" => ["this"]})
  end
end

describe "reference: issue regressions" do
  it "issue 40: prefix matching picks the unique prefix" do
    docopt_for("usage: prog --help-commands | --help", "--help")
      .should eq({"--help-commands" => false, "--help" => true})
    docopt_for("usage: prog --aabb | --aa", "--aa")
      .should eq({"--aabb" => false, "--aa" => true})
  end

  it "issue 59: empty option arguments" do
    docopt_for("usage: prog --long=<a>", "--long=").should eq({"--long" => ""})
    Docopt.docopt("usage: prog -l <a>\noptions: -l <a>", ["-l", ""], help: false, exit: false)
      .should eq({"-l" => ""})
  end

  it "issue 71: -- is not a valid option argument" do
    expect_raises(Docopt::DocoptExit) do
      docopt_for("usage: prog [--log=LEVEL] [--] <args>...", "--log -- 1 2")
    end
    expect_raises(Docopt::DocoptExit) do
      docopt_for("usage: prog [-l LEVEL] [--] <args>...\noptions: -l LEVEL", "-l -- 1 2")
    end
  end

  it "issue 68: [options] does not include options from the usage pattern" do
    docopt_for("usage: prog [-ab] [options]\noptions: -x\n -y", "-ax")
      .should eq({"-a" => true, "-b" => false, "-x" => true, "-y" => false})
  end

  it "issue 126: defaults are parsed when options are tab-indented" do
    Docopt.parse_defaults("Options:\n\t--foo=<arg>  [default: bar]")
      .should eq([Docopt::Option.new(nil, "--foo", 1, "bar")])
  end

  it "issue 34: unicode arguments" do
    docopt_for("usage: prog [-o <a>]", "").should eq({"-o" => false, "<a>" => nil})
  end
end

describe "reference: options_first" do
  it "keeps options before positional arguments when requested" do
    doc = "usage: prog [--opt] [<args>...]"
    docopt_for(doc, "--opt this that").should eq({"--opt" => true, "<args>" => ["this", "that"]})
    docopt_for(doc, "this that --opt").should eq({"--opt" => true, "<args>" => ["this", "that"]})
    Docopt.docopt(doc, "this that --opt".split, help: false, options_first: true, exit: false)
      .should eq({"--opt" => false, "<args>" => ["this", "that", "--opt"]})
  end
end

describe "reference: section parsing" do
  it "finds every usage section" do
    Docopt.parse_section("usage:", "foo bar fizz buzz").should eq([] of String)
    Docopt.parse_section("usage:", "usage: prog").should eq(["usage: prog"])
    Docopt.parse_section("usage:", "usage: -x\n -y").should eq(["usage: -x\n -y"])
  end

  it "finds usage sections in mixed-case, tab-indented documents" do
    doc = <<-USAGE
      usage: this

      usage:hai
      usage: this that

      usage: foo
             bar

      PROGRAM USAGE:
       foo
       bar
      usage:
      \ttoo
      \ttar
      Usage: eggs spam
      BAZZ
      usage: pit stop
      USAGE
    Docopt.parse_section("usage:", doc).should eq([
      "usage: this",
      "usage:hai",
      "usage: this that",
      "usage: foo\n       bar",
      "PROGRAM USAGE:\n foo\n bar",
      "usage:\n\ttoo\n\ttar",
      "Usage: eggs spam",
      "usage: pit stop",
    ])
  end

  it "rewrites the usage section into a pattern expression" do
    doc = "\n    Usage: prog [-hv] ARG\n           prog N M\n\n    prog is a program."
    usage = Docopt.parse_section("usage:", doc)[0]
    usage.should eq "Usage: prog [-hv] ARG\n           prog N M"
    Docopt.formal_usage(usage).should eq "( [-hv] ARG ) | ( N M )"
  end
end

describe "reference: pattern matching" do
  it "matches options" do
    option = Docopt::Option.new("-a")
    option.match([Docopt::Option.new("-a", nil, 0, true)] of Docopt::Pattern)
      .should eq({true, [] of Docopt::Pattern, [Docopt::Option.new("-a", nil, 0, true)] of Docopt::Pattern})
    option.match([Docopt::Option.new("-x")] of Docopt::Pattern)
      .should eq({false, [Docopt::Option.new("-x")] of Docopt::Pattern, [] of Docopt::Pattern})
    option.match([Docopt::Argument.new("N")] of Docopt::Pattern)
      .should eq({false, [Docopt::Argument.new("N")] of Docopt::Pattern, [] of Docopt::Pattern})
    option.match([Docopt::Option.new("-x"), Docopt::Option.new("-a"), Docopt::Argument.new("N")] of Docopt::Pattern)
      .should eq({true, [Docopt::Option.new("-x"), Docopt::Argument.new("N")] of Docopt::Pattern,
                  [Docopt::Option.new("-a")] of Docopt::Pattern})
  end

  it "matches arguments" do
    argument = Docopt::Argument.new("N")
    argument.match([Docopt::Argument.new(nil, "9")] of Docopt::Pattern)
      .should eq({true, [] of Docopt::Pattern, [Docopt::Argument.new("N", "9")] of Docopt::Pattern})
    argument.match([Docopt::Argument.new(nil, "9"), Docopt::Argument.new(nil, "0")] of Docopt::Pattern)
      .should eq({true, [Docopt::Argument.new(nil, "0")] of Docopt::Pattern,
                  [Docopt::Argument.new("N", "9")] of Docopt::Pattern})
  end

  it "matches commands" do
    command = Docopt::Command.new("c")
    command.match([Docopt::Argument.new(nil, "c")] of Docopt::Pattern)
      .should eq({true, [] of Docopt::Pattern, [Docopt::Command.new("c", true)] of Docopt::Pattern})
    command.match([Docopt::Argument.new(nil, "x")] of Docopt::Pattern)
      .should eq({false, [Docopt::Argument.new(nil, "x")] of Docopt::Pattern, [] of Docopt::Pattern})
  end

  it "accumulates list arguments" do
    Docopt::Required.new([Docopt::Argument.new("N"), Docopt::Argument.new("N")] of Docopt::Pattern)
      .fix.match([Docopt::Argument.new(nil, "1"), Docopt::Argument.new(nil, "2")] of Docopt::Pattern)
      .should eq({true, [] of Docopt::Pattern, [Docopt::Argument.new("N", ["1", "2"])] of Docopt::Pattern})
    Docopt::OneOrMore.new([Docopt::Argument.new("N")] of Docopt::Pattern)
      .fix.match([Docopt::Argument.new(nil, "1"), Docopt::Argument.new(nil, "2"), Docopt::Argument.new(nil, "3")] of Docopt::Pattern)
      .should eq({true, [] of Docopt::Pattern, [Docopt::Argument.new("N", ["1", "2", "3"])] of Docopt::Pattern})
  end

  it "shares one object for equal leaves after fix_identities" do
    pattern = Docopt::Required.new([Docopt::Argument.new("N"), Docopt::Argument.new("N")] of Docopt::Pattern)
    children = pattern.children.as(Array(Docopt::Pattern))
    children[0].should_not eq children[1].object_id
    pattern.fix_identities
    children[0].object_id.should eq children[1].object_id
  end
end
