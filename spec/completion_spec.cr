# Completion script tests against real shells.
#
# bash completions are executed through the same COMP_WORDS/COMP_CWORD
# protocol bash itself uses, and fish scripts through `complete -C`.
# zsh scripts are at least parsed with `zsh -n` (a pty-driven zsh
# completion session proved too timing-sensitive for automated runs);
# all three generators share the tree building and dispatch walk that
# the bash and fish tests exercise end to end. Tests skip when the
# shell is not installed (the CI containers only have bash).

require "./spec_helper"
require "file_utils"

COMPLETION_DOC = <<-DOC
  Naval Fate.

  Usage:
    naval_fate ship new <name>...
    naval_fate ship <name> move <x> <y> [--speed=<kn>]
    naval_fate ship shoot <x> <y>
    naval_fate mine (set|remove) <x> <y> [--moored|--drifting]
    naval_fate mine list
    naval_fate fleet status
    naval_fate save [--files=files...]
    naval_fate set_speed [--speed=<kn>]
    naval_fate -h | --help
    naval_fate --version

  Options:
    -h --help           Show this screen.
    --version           Show version.
    -s,--speed=<kn>     Speed in knots [default: 10].
    --moored            Moored (anchored) mine.
    --drifting          Drifting mine.
    --files=<files>     List of files to save.
  DOC

STRESS_DOC = <<-DOC
  Stress.

  Usage:
    stress [--level=<x>] go <place>
    stress [--level=<x>] stop

  Options:
    --level=<x>  Level [default: low].
  DOC

CUSTOM_COMPLETIONS = {
  "naval_fate_ship_new" => "USS Enterprise USS Missouri",
  "--speed"             => "5 10 15 20",
  "--files"             => "a.txt b.txt",
  "--level"             => "low normal high",
  "stress_go"           => "home work",
}

def shell_available?(name : String) : Bool
  Process.run("sh", ["-c", "command -v #{name} > /dev/null 2>&1"]).success?
end

def run_shell(command : String, args : Array(String)) : Tuple(Int32, String, String)
  output = IO::Memory.new
  error = IO::Memory.new
  status = Process.run(command, args, output: output, error: error)
  {status.exit_code, output.to_s, error.to_s}
end

def with_completion_workdir(& : String -> Nil) : Nil
  dir = File.join(Dir.tempdir, "docopt-completion-#{Random::Secure.hex(8)}")
  Dir.mkdir_p(dir)
  begin
    yield dir
  ensure
    FileUtils.rm_rf(dir)
  end
end

# Run the generated bash completion function the way bash's
# `complete -F` would: *words* is the argv after the command name,
# where the last entry is the word being completed ("" for empty).
def bash_complete(script : String, completion_function : String, words : Array(String)) : Tuple(Array(String), String)
  words_before = words.size > 1 ? words[0..-2] : [] of String
  cur = words[-1]
  driver = String.build do |io|
    io << "source #{script.inspect}\n"
    io << <<-HARNESS
      run_completion() {
          local completion_function=$1 words_before=$2 cur=$3
          local -a comp_words=(dummy)
          if [ -n "$words_before" ]; then
              for word in $words_before; do
                  comp_words+=("$word")
              done
          fi
          local cword=${#comp_words[@]}
          if [ -n "$cur" ]; then
              comp_words+=("$cur")
          fi
          COMP_WORDS=("${comp_words[@]}")
          COMP_CWORD=$cword
          COMP_LINE="dummy $words_before $cur"
          COMP_POINT=${#COMP_LINE}
          COMPREPLY=()
          "$completion_function"
          echo "-> ${COMPREPLY[*]}"
      }
      HARNESS
    io << "\n"
    io << "run_completion #{completion_function} \"#{words_before.join(" ")}\" \"#{cur}\"\n"
  end
  _status, output, error = run_shell("bash", ["-c", driver])
  replies = output.lines.select(&.starts_with?("-> ")).flat_map(&.[3..].strip.split)
  {replies, error}
end

def fish_complete(script : String, command_line : String) : Array(String)
  _status, output, _error = run_shell("fish", ["-c", "source #{script.inspect}; and complete -C '#{command_line}'"])
  output.lines.map(&.strip.split('\t').first).reject(&.empty?)
end

describe "completion doc-to-tree extraction" do
  it "expands [options] shortcuts into the node's options" do
    doc = <<-DOC
      Usage: prog [options] go

      Options:
        --fast  Go fast.
        --slow  Go slow.
      DOC
    tree, _option_help = Docopt::BashCompletion.new(doc).parse_params
    tree.option_specs.map(&.name.to_s).sort!.should eq ["--fast", "--slow"]
    tree.subcommands.keys.should eq ["go"]
  end

  it "raises DocoptLanguageError for docs without a usage section" do
    expect_raises(Docopt::DocoptLanguageError) do
      Docopt.bash_completion("prog", "no usage section here")
    end
  end
end

describe "bash completion script" do
  it "completes like bash would call it" do
    with_completion_workdir do |dir|
      script = File.join(dir, "naval_fate.sh")
      File.write(script, Docopt.bash_completion("naval_fate", COMPLETION_DOC, CUSTOM_COMPLETIONS))

      replies, error = bash_complete(script, "_naval_fate", [""])
      replies.should eq ["-h", "--help", "--version", "ship", "mine", "fleet", "save", "set_speed"]
      # The else-glue bug made bash run "else" as a command on every TAB
      error.should_not contain("command not found")

      replies, _error = bash_complete(script, "_naval_fate", ["sh"])
      replies.should eq ["ship"]

      # ship's own words: subcommands plus files (<name> takes one)
      replies, _error = bash_complete(script, "_naval_fate", ["ship", ""])
      replies.should contain "new"
      replies.should contain "move"
      replies.should contain "shoot"

      # custom ship names, at ship new
      replies, _error = bash_complete(script, "_naval_fate", ["ship", "new", ""])
      replies.should eq ["USS", "Enterprise", "USS", "Missouri"]

      # options are completed, also past positional arguments
      replies, _error = bash_complete(script, "_naval_fate", ["ship", "X", "move", "1", "2", "--spe"])
      replies.should eq ["--speed="]
      replies, _error = bash_complete(script, "_naval_fate", ["ship", "X", "move", "1", "2", "--speed", ""])
      replies.should eq ["5", "10", "15", "20"]
      replies, _error = bash_complete(script, "_naval_fate", ["ship", "X", "move", "1", "2", "--speed=1"])
      replies.should eq ["--speed=10", "--speed=15"]

      # short options complete their values too
      replies, _error = bash_complete(script, "_naval_fate", ["set_speed", "-s", ""])
      replies.should eq ["5", "10", "15", "20"]

      # other options with arguments complete their custom values
      replies, _error = bash_complete(script, "_naval_fate", ["save", "--files", ""])
      replies.should eq ["a.txt", "b.txt"]
    end
  end

  it "keeps subcommands when an option has a custom completion" do
    with_completion_workdir do |dir|
      script = File.join(dir, "stress.sh")
      File.write(script, Docopt.bash_completion("stress", STRESS_DOC, CUSTOM_COMPLETIONS))
      replies, _error = bash_complete(script, "_stress", [""])
      replies.should contain "--level="
      replies.should contain "go"
      replies.should contain "stop"
    end
  end
end

describe "fish completion script" do
  # Skipped when fish is not installed (CI containers only ship bash)
  if shell_available?("fish")
    it "completes through fish's complete -C" do
      with_completion_workdir do |dir|
        script = File.join(dir, "naval_fate.fish")
        File.write(script, Docopt.fish_completion("naval_fate", COMPLETION_DOC, CUSTOM_COMPLETIONS))

        # Top level: subcommands (and no file fallback)
        fish_complete(script, "naval_fate ").sort.should eq ["fleet", "mine", "save", "set_speed", "ship"]

        # One level deep, without the ship-new custom leaking in
        words = fish_complete(script, "naval_fate ship ")
        words.should contain "new"
        words.should contain "move"
        words.should contain "shoot"
        words.should_not contain "Enterprise"

        # Custom positional completions
        fish_complete(script, "naval_fate ship new ").sort.should eq ["Enterprise", "Missouri", "USS"]

        # Option values, both separated and --opt= attached
        words = fish_complete(script, "naval_fate set_speed --speed ")
        words.should contain "5"
        words.should contain "10"
        fish_complete(script, "naval_fate set_speed --speed=").should contain "--speed=5"
      end
    end

    it "keeps subcommands when an option has a custom completion" do
      with_completion_workdir do |dir|
        script = File.join(dir, "stress.fish")
        File.write(script, Docopt.fish_completion("stress", STRESS_DOC, CUSTOM_COMPLETIONS))
        words = fish_complete(script, "stress ")
        words.should contain "go"
        words.should contain "stop"
      end
    end
  end
end

describe "zsh completion script" do
  # Skipped when zsh is not installed (CI containers only ship bash)
  if shell_available?("zsh")
    it "parses and defines every function once" do
      with_completion_workdir do |dir|
        script = File.join(dir, "_naval_fate")
        content = Docopt.zsh_completion("naval_fate", COMPLETION_DOC, CUSTOM_COMPLETIONS)
        File.write(script, content)

        status, _output, error = run_shell("zsh", ["-n", script])
        status.should eq 0
        error.should be_empty

        # every generated function appears exactly once
        content.scan(/^(_[a-zA-Z0-9_]+)\(\) \{$/).map(&.[1]).each do |name|
          content.scan(/^#{name}\(\) \{$/).size.should eq 1
        end

        # the state machine and dispatch walk are present
        content.should contain "':command:->command'"
        content.should contain "'*::rest:->rest'"
        content.should contain("(ship) _naval_fate_ship ;;")
      end
    end
  end
end
