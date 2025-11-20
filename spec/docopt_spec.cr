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
    farr = ans["--files"].as(Array(String))
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

  it("should raise exception if not match") do
    expect_raises(Exception) do
      Docopt.docopt("", ["ship"], help: false, exit: false)
    end
  end

  it "should parse option_help" do
    bash_completion = Docopt::BashCompletion.new full_doc
    _, option_help = bash_completion.parse_params
    # The python version uses "--speed=" but this looks good enough
    expected = {"--drifting" => "Drifting mine.",
                "--help"     => "Show this screen.",
                "--moored"   => "Moored (anchored) mine.",
                "--speed"    => "Speed in knots [default: 10].",
                "--version"  => "Show version.",
                "-h"         => "Show this screen.",
                "-s"         => "Speed in knots [default: 10].",
    }
    option_help.size.should eq expected.size
    option_help.each do |key, value|
      expected[key].should eq value
    end
  end

  it "should parse param_tree" do
    bash_completion = Docopt::BashCompletion.new full_doc
    param_tree, _ = bash_completion.parse_params

    expected = %(cmds:
    init:
         cmds:
         args: []
         opts: ["-v"]

    ship:
         cmds:
             new:
                 cmds:
                 args: ["<name>"]
                 opts: []

             move:
                  cmds:
                  args: ["<x>", "<y>"]
                  opts: ["-s=", "--speed="]

             shoot:
                   cmds:
                   args: ["<x>", "<y>"]
                   opts: []

         args: ["<name>"]
         opts: []

    mine:
         cmds:
             set:
                 cmds:
                 args: []
                 opts: []

             remove:
                    cmds:
                    args: []
                    opts: []

         args: ["<x>", "<y>"]
         opts: ["--moored", "--drifting"]

    save:
         cmds:
         args: []
         opts: ["--files="]

    set_speed:
              cmds:
              args: []
              opts: ["-s=", "--speed="]

args: []
opts: ["-h", "--help", "-h", "--help", "--version"]
)
    expected.should eq param_tree.repr
  end

  it "should create bash completion" do
    bash_completion = Docopt.bash_completion("x", full_doc)
    bash_completion.should_not be_nil
    # Test that basic bash completion structure is created
    bash_completion.should contain("_x()")
    bash_completion.should contain("COMPREPLY=")
    bash_completion.should contain("compgen -W")
    bash_completion.should contain("init")
    bash_completion.should contain("ship")
  end

  it "should insert custom completion commands" do
    expected = <<-EXPECTED
_x_init()
{
    local cur
    cur="${COMP_WORDS[COMP_CWORD]}"

    if [ $COMP_CWORD -ge 2 ]; then
        COMPREPLY=( $( compgen -W "$(ls -l /)" -- $cur) )
    fi
}
EXPECTED

    bash_completion = Docopt.bash_completion("x", full_doc, {"x_init" => "$(ls -l /)"})
    bash_completion.should_not be_nil
    (bash_completion.includes? expected).should be_true
  end

  # Fish completion tests
  it "should create fish completion" do
    fish_completion = Docopt.fish_completion("naval_fate", full_doc)
    fish_completion.should_not be_nil
    fish_completion.should contain("complete -c naval_fate")
    fish_completion.should contain("fish")
    fish_completion.should contain("Generated by docopt.cr")
  end

  it "should parse option_help for fish completion" do
    fish_completion = Docopt::FishCompletion.new full_doc
    _, option_help = fish_completion.parse_params
    expected_keys = ["--drifting", "--help", "--moored", "--speed", "--version", "-h", "-s"]

    expected_keys.each do |key|
      option_help.keys.should contain(key)
    end
  end

  it "should create fish completion with subcommands" do
    fish_completion = Docopt.fish_completion("naval_fate", full_doc)
    fish_completion.should contain("__fish_seen_subcommand_from naval_fate")
    fish_completion.should contain("__fish_seen_subcommand_from ship")
    fish_completion.should contain("__fish_seen_subcommand_from mine")
    fish_completion.should contain("complete -c naval_fate -f -n")
  end

  it "should insert custom fish completion commands" do
    custom_completions = {"naval_fate_ship_new" => "$(ls ships)"}
    fish_completion = Docopt.fish_completion("naval_fate", full_doc, custom_completions)
    fish_completion.should contain("$(ls ships)")
  end

  # ZSH completion tests
  it "should create zsh completion" do
    zsh_completion = Docopt.zsh_completion("naval_fate", full_doc)
    zsh_completion.should_not be_nil
    zsh_completion.should contain("#compdef naval_fate")
    zsh_completion.should contain("_naval_fate")
    zsh_completion.should contain("Generated by docopt.cr")
  end

  it "should parse option_help for zsh completion" do
    zsh_completion = Docopt::ZshCompletion.new full_doc
    _, option_help = zsh_completion.parse_params
    expected_keys = ["--drifting", "--help", "--moored", "--speed", "--version", "-h", "-s"]

    expected_keys.each do |key|
      option_help.keys.should contain(key)
    end
  end

  it "should create zsh completion with command arguments" do
    zsh_completion = Docopt.zsh_completion("naval_fate", full_doc)
    zsh_completion.should contain("'ship:ship'")
    zsh_completion.should contain("'mine:mine'")
    zsh_completion.should contain("'init:init'")
  end

  it "should create zsh completion with option arguments" do
    zsh_completion = Docopt.zsh_completion("naval_fate", full_doc)
    zsh_completion.should contain("'--help[Show this screen.]'")
    zsh_completion.should contain("'--version[Show version.]'")
    # ZSH completion might have a slightly different format for options with arguments
    zsh_completion.should contain("--speed")
  end

  it "should insert custom zsh completion commands" do
    custom_completions = {"naval_fate_ship_new" => "$(ls ships)"}
    zsh_completion = Docopt.zsh_completion("naval_fate", full_doc, custom_completions)
    zsh_completion.should contain("$(ls ships)")
  end

  # Integration tests
  it "should produce different completion scripts for different shells" do
    bash_completion = Docopt.bash_completion("test", full_doc)
    fish_completion = Docopt.fish_completion("test", full_doc)
    zsh_completion = Docopt.zsh_completion("test", full_doc)

    bash_completion.should_not eq(fish_completion)
    fish_completion.should_not eq(zsh_completion)
    bash_completion.should_not eq(zsh_completion)
  end

  it "should handle custom completions consistently across shells" do
    custom_completions = {"test_ship_new" => "$(echo custom)"}

    bash_completion = Docopt.bash_completion("test", full_doc, custom_completions)
    fish_completion = Docopt.fish_completion("test", full_doc, custom_completions)
    zsh_completion = Docopt.zsh_completion("test", full_doc, custom_completions)

    bash_completion.should contain("$(echo custom)")
    fish_completion.should contain("$(echo custom)")
    zsh_completion.should contain("$(echo custom)")
  end

  # Custom option completion tests
  it "should support custom completions for options with arguments (fish)" do
    doc_with_option = <<-DOC
    Tool with custom option completion.

    Usage:
      tool [--theme=<theme>]

    Options:
      --theme=<theme>  Set the theme [default: auto].
    DOC

    custom_completions = {"--theme" => "dark light auto"}
    fish_completion = Docopt.fish_completion("tool", doc_with_option, custom_completions)

    fish_completion.should contain("complete -c tool -l theme -d '--theme='")
    fish_completion.should contain("complete -c tool -f -n '__fish_seen_subcommand_from tool and __fish_seen_option -l theme' -a 'dark light auto'")
  end

  it "should support custom completions for options with arguments (bash)" do
    doc_with_option = <<-DOC
    Tool with custom option completion.

    Usage:
      tool [--theme=<theme>]

    Options:
      --theme=<theme>  Set the theme [default: auto].
    DOC

    custom_completions = {"--theme" => "dark light auto"}
    bash_completion = Docopt.bash_completion("tool", doc_with_option, custom_completions)

    bash_completion.should contain("--theme=dark light auto")
  end

  it "should support custom completions for options with arguments (zsh)" do
    doc_with_option = <<-DOC
    Tool with custom option completion.

    Usage:
      tool [--theme=<theme>]

    Options:
      --theme=<theme>  Set the theme [default: auto].
    DOC

    custom_completions = {"--theme" => "dark light auto"}
    zsh_completion = Docopt.zsh_completion("tool", doc_with_option, custom_completions)

    zsh_completion.should contain("'--theme=[--theme=]:{$(dark light auto)}'")
  end

  it "should support custom completions for short options with arguments" do
    doc_with_short_option = <<-DOC
    Tool with custom short option completion.

    Usage:
      tool [-t=<theme>]

    Options:
      -t=<theme>  Set the theme [default: auto].
    DOC

    custom_completions = {"-t" => "dark light auto"}

    # Test all three shells
    fish_completion = Docopt.fish_completion("tool", doc_with_short_option, custom_completions)
    bash_completion = Docopt.bash_completion("tool", doc_with_short_option, custom_completions)
    zsh_completion = Docopt.zsh_completion("tool", doc_with_short_option, custom_completions)

    fish_completion.should contain("__fish_seen_option -s t")
    fish_completion.should contain("dark light auto")

    bash_completion.should contain("-t dark light auto")

    zsh_completion.should contain("'-t[-t=]:{$(dark light auto)}'")
  end

  it "should not apply custom completions to options without arguments" do
    doc_with_no_arg_option = <<-DOC
    Tool with boolean option.

    Usage:
      tool [--verbose]

    Options:
      --verbose  Enable verbose output.
    DOC

    custom_completions = {"--verbose" => "should not appear"}
    fish_completion = Docopt.fish_completion("tool", doc_with_no_arg_option, custom_completions)

    # Should have the basic option but no custom completion
    fish_completion.should contain("complete -c tool -l verbose -d 'Enable verbose output.'")
    fish_completion.should_not contain("should not appear")
  end

  it "should support mixed option custom completions" do
    doc_with_mixed_options = <<-DOC
    Tool with mixed options.

    Usage:
      tool [--theme=<theme>] [--verbose] [--template=<template>]

    Options:
      --theme=<theme>    Set the theme [default: auto].
      --verbose          Enable verbose output.
      --template=<template>  Set the template [default: basic].
    DOC

    custom_completions = {
      "--theme"    => "dark light auto",
      "--template" => "basic advanced custom",
    }

    fish_completion = Docopt.fish_completion("tool", doc_with_mixed_options, custom_completions)

    # Should have custom completions for options with arguments
    fish_completion.should contain("dark light auto")
    fish_completion.should contain("basic advanced custom")

    # Should have basic option without custom completion
    fish_completion.should contain("complete -c tool -l verbose")
  end
end
