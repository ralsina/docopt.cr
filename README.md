# docopt.cr

docopt for crystal-lang

This is a fork of the original [docopt.cr by chenkovsky](https://github.com/chenkovsky/docopt.cr) with a few bugfixes.


It has a couple of bugfixes and I am now starting to add new features:

* bash completion generation
* fish completion generation
* zsh completion generation
* Custom hooks for smarter completion


## Installation


Add this to your application's `shard.yml`:

```yaml
dependencies:
  docopt:
    github: ralsina/docopt.cr
```


## Usage


```crystal
require "docopt"
describe "Docopt" do
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
    std = {"ship" => true, "new" => false, "<name>" => ["A"], "move" => true, "<x>" => "a", "<y>" => "b", "--speed" => "3", "shoot" => false, "mine" => false, "set" => false, "remove" => false, "--moored" => nil, "--drifting" => nil, "-h" => nil, "--help" => false, "--version" => nil}
    ans = Docopt.docopt(doc, argv = ["ship", "A", "move", "a", "b", "--speed=3"])
    ans["<name>"].should eq(std["<name>"])
  end
  it "one or more" do
    doc = <<-DOC
    test
    Usage:
        naval [--files=files...]
    DOC
    ans = Docopt.docopt(doc, argv = ["--files=a.txt", "--files=b.txt"])
    farr = ans["--files"] as Array(String)
    "a.txt".should eq(farr[0])
    "b.txt".should eq(farr[1])
  end
end
```

## Compile-time parsing

`Docopt.docopt` parses the usage text on every run, which for a
program with a couple of dozen options costs a few milliseconds of
startup. The usage text is almost always a constant, so it can be
parsed while compiling instead:

```crystal
require "docopt"

USAGE = <<-DOC
  Usage: prog [-v] <file>...

  Options:
    -v  Verbose.
  DOC

COMPILED = Docopt.compile(USAGE)
options = Docopt.match(COMPILED, ARGV)
```

`Docopt.compile` is a macro. It takes a string literal, or a constant
assigned one, parses it at compile time and embeds the resulting
pattern in the binary, so at runtime only the argument matching runs.
An invalid usage text becomes a compilation error instead of a runtime
one. `Docopt.match` accepts the same `help`, `version`,
`options_first` and `exit` arguments as `Docopt.docopt` and returns the
same hash.

For a 17-line usage text with 21 options, `Docopt.docopt` costs about
1.6 ms per call and `Docopt.match` on the compiled pattern about
0.02 ms.

The two halves are also available at runtime as `Docopt.parse(doc)`,
which returns a `Docopt::Compiled`, and `Docopt.match(compiled, argv)`,
for programs that match many argument vectors against one usage text.

A `Compiled` pattern also exposes what the doc declares, so layered
tools (configuration files, environment variables, subcommand
dispatchers) never need to re-parse the doc:

- `compiled.defaults` — the value every declared option parses to when
  absent from argv: its `[default: ...]` value (an array for repeated
  options), `false` for flags, `nil` otherwise.
- `compiled.without_defaults` — a copy of the pattern with declared
  defaults neutralized, so matching tells "given on the command line"
  apart from "fell back to the default". Equivalent to matching the
  same doc with the `[default: ...]` annotations stripped.

```crystal
compiled = Docopt.parse(USAGE)
given = Docopt.match(compiled.without_defaults, ARGV, exit: false)
speed = given["--speed"]? || compiled.defaults["--speed"]
```

## Configuration Layer

`require "docopt/config"` layers YAML configuration files and
environment variables under docopt's command-line parsing, with the
precedence **CLI > environment > config file > docopt defaults**:

```crystal
require "docopt/config"

options = Docopt.docopt_config(USAGE,
  argv: ARGV,
  config_file_path: "config.yml",
  env_prefix: "MYAPP"
)

options["--verbose"] # CLI value when given, else env, else file, else default
```

Config keys map to options in any of three shapes (`verbose`,
`--verbose`, `input_file` for `--input-file`); values are coerced to
the type docopt would produce (booleans for flags, arrays for
repeatable options). Environment variables map from
`MYAPP_INPUT_FILE`-style names with the same coercion, and
`--print-config`-style flags can dump the fully-resolved configuration
as a working config file.

The usage text can be parsed once at compile time, like the core:

```crystal
CONFIG = Docopt.compile_config(USAGE)
options = Docopt.docopt_config(CONFIG, argv: ARGV, env_prefix: "MYAPP")
```

See the docopt-config shard's README for the full tier semantics; the
code and tests now live here.

## Subcommand Dispatch

`require "docopt/dispatch"` builds git-style tools where every
subcommand has its own complete docopt help text:

```crystal
require "docopt/dispatch"

struct Hello < Docopt::Dispatch::Command
  @@name = "hello"
  @@doc = <<-HELP
    Says hello to the world

    Usage:
      say hello [--shout]

    Options:
      --shout  SHOUT IT
    HELP

  def run : Int32
    puts(options["--shout"] ? "HELLO WORLD" : "hello world")
    0
  end
end

Hello.register

exit(Docopt::Dispatch.main("say", ARGV))
```

Dispatch handles the `help [COMMAND]` command, `-h`/`--help`,
git-style "most similar command" suggestions for typos, and exit codes
(commands propagate their `run` return value; errors exit 1). Each
command's doc is parsed once and cached (`Command.compiled`), so
dispatching is a plain argv match. Help requests are not honored
after a `--` separator. This layer grew out of the polydocopt shard;
its README has the full behavior table.

Dispatch composes with the completion generators: one script covers
the whole command tree, with each command's options and arguments
coming from its own doc, and custom completions keyed by command path
(`"say_hello"`):

```crystal
puts Docopt::Dispatch.bash_completion("say")
puts Docopt::Dispatch.fish_completion("say", {"say_hello" => "world mars"})
puts Docopt::Dispatch.zsh_completion("say")
```

The typo machinery is reusable: `Dispatch.suggestions_for(attempted,
candidates)` returns the close matches for any word list (closest
first, ties alphabetically, at most four, within a distance of
`max(size // 3, 2)`), defaulting to the registered commands.

See `examples/dispatch` for a complete tool with completion flags.

## Shell Completion Generation

docopt.cr can generate shell completion scripts for bash, fish, and zsh
so that when you `TAB` while writing a command it will show you the possible
options.

### Bash Completion

The code to create a bash completion looks like this for the classic
`naval_fate` example:

```crystal
    bash_completion = Docopt.bash_completion("naval_fate", doc)
```

To make this available to the user you could have something like a `naval_fate --completion-bash`
in your usage instructions and either tell the user to put this in their `.bashrc`:

```bash
    naval_fate --completion-bash >> ~/.bashrc
```

Or write it to a file and put it in /etc/bash_completion.d/:

```bash
    naval_fate --completion-bash > /etc/bash_completion.d/naval_fate
```

### Fish Completion

For fish shell completion:

```crystal
    fish_completion = Docopt.fish_completion("naval_fate", doc)
```

Users can install fish completions by adding to their config:

```bash
    naval_fate --completion-fish > ~/.config/fish/completions/naval_fate.fish
```

### ZSH Completion

For zsh shell completion:

```crystal
    zsh_completion = Docopt.zsh_completion("naval_fate", doc)
```

Users can install zsh completions by adding:

```bash
    naval_fate --completion-zsh > ~/.local/share/zsh/site-functions/_naval_fate
```

Or system-wide:

```bash
    naval_fate --completion-zsh > /usr/share/zsh/site-functions/_naval_fate
```

## Custom Completions

Usually the suggestions provided by the completions are limited to
flags options and files, which may not be the right thing.

Suppose you want the `naval_fate ship new` command to be completed with 
just the names from a list of famous ships. You can do that using the
`custom_completions` argument:

```crystal
    bash_completion = Docopt.bash_completion(
      "naval_fate", 
      doc, 
      {"naval_fate_ship_new" => %("Titanic 'Queen Mary' 'USS Enterprise')}
    )
```

The key is the name of the command and any subcommands, joined by
`_` (underscore). In this case, the command is `naval_fate ship new`.

The completion should be provided as a list of space-separated strings,
and if any of them contain spaces, they should be *single-quoted*.

It can be made more dynamic by using instead the *output of a command*.
For example, if the command `naval_fate ship list` existed, we could do this
using `bash` ability to run commands inside other commands:

```crystal
    bash_completion = Docopt.bash_completion(
      "naval_fate", 
      doc, 
      {"naval_fate_ship_new" => "$(naval_fate ship list)"}
    )
```

And the completion for `naval_fate ship new` would be the output of
`naval_fate ship list`.

### Custom Completions for All Shells

The custom completion system works consistently across all three shells:

```crystal
    # Define custom completions once
    completions = {
      "naval_fate_ship_new" => "$(naval_fate ship list)",
      "naval_fate_mine_set" => %("anchored drifting")
    }

    # Use with any shell
    bash_completion = Docopt.bash_completion("naval_fate", doc, completions)
    fish_completion = Docopt.fish_completion("naval_fate", doc, completions)
    zsh_completion = Docopt.zsh_completion("naval_fate", doc, completions)
```

This ensures consistent completion behavior regardless of which shell the user prefers.

## Examples

See the `examples/` directory for a complete working example:

### Naval Fate CLI

The `naval_fate` application demonstrates real-world usage:

```bash
# Build and run the example
cd examples
crystal build naval_fate.cr -o naval_fate
./naval_fate --help

# Generate completions
./naval_fate --completion-bash > ~/.bash_completion.d/naval_fate
./naval_fate --completion-fish > ~/.config/fish/completions/naval_fate.fish
./naval_fate --completion-zsh > ~/.local/share/zsh/site-functions/_naval_fate
```

Features demonstrated:
- Multi-subcommand CLI structure
- Custom completions with dynamic ship names
- Real-time fleet management
- Shell-appropriate completion behaviors

Run `examples/test_completion.sh` to see a complete demonstration of the completion functionality.

## Development

### Building

```bash
crystal build src/docopt.cr
crystal spec  # Run tests
ameba --fix  # Run linter
```

## Contributing

1. Fork it ( https://github.com/ralsina/docopt.cr/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [chenkovsky](https://github.com/chenkovsky) chenkovsky.chen - creator, maintainer
- [ralsina](https://github.com/ralsina) Roberto Alsina - fork maintainer
