# docopt.cr

[![CI](https://github.com/ralsina/docopt.cr/actions/workflows/ci.yml/badge.svg)](https://github.com/ralsina/docopt.cr/actions/workflows/ci.yml)
[![GitHub tag](https://img.shields.io/github/v/tag/ralsina/docopt.cr)](https://github.com/ralsina/docopt.cr/tags)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

docopt for crystal-lang: command-line interfaces declared as help
text, with everything that grows on top of them.

A fork of the original [docopt.cr by chenkovsky](https://github.com/chenkovsky/docopt.cr),
conformant with the official docopt test suite, that grew:

* compile-time parsing (`Docopt.compile`, `Docopt.compile_config`)
* working bash, fish and zsh completion generation, including
  subcommand-aware completion for dispatch tools
* the configuration layer (`require "docopt/config"`): YAML config
  files and environment variables under CLI precedence
* subcommand dispatch (`require "docopt/dispatch"`): git-style
  command trees with help, typo suggestions and exit codes
* both together (`require "docopt/dispatch_config"`): every
  command's options resolved through the full precedence chain

See the [changelog](CHANGELOG.md) for release history.

## Installation

Add this to your application's `shard.yml`:

```yaml
dependencies:
  docopt:
    github: ralsina/docopt.cr
    version: "~> 1.0"
```


## Usage

Declare your interface as its own help text; docopt parses argv
against it and hands you the values:

```crystal
require "docopt"

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

options = Docopt.docopt(doc, ARGV)
if options["--version"]
  puts "naval_fate 1.0"
elsif options["ship"] && options["move"]
  speed = options["--speed"].as(String)
  puts "Moving #{options["<name>"]} to #{options["<x>"]},#{options["<y>"]} at #{speed} knots"
end
```

Flags parse as booleans, options with arguments as strings, repeated
elements as arrays and counting flags as integers; unmatched argv
prints the usage and exits (or raises `Docopt::DocoptExit` with
`exit: false`).

## Error Messages

Failed matches explain what went wrong instead of only dumping the
usage: unknown options and unexpected arguments are named, and close
typos get a "did you mean" hint computed against the declared options
and commands.

```
$ prog --verbso
Unknown option --verbso. Did you mean --verbose?
Usage:
  prog [--verbose] [--version]
  ...
```

The matcher behind the hints is public and domain independent:
`Docopt.suggestions_for(attempted, candidates)` returns the close
matches (closest first, ties alphabetically, at most four, within a
distance of `max(size // 3, 2)`).

## Typed Access

Instead of `.as(String)` casts and their generic failures, ask the
result for the type you want; a wrong ask raises a `TypeMismatchError`
naming the option, the value and its actual type.

```crystal
options = Docopt.docopt(doc, ARGV)
speed = options.string("--speed")
count = options.int("-v")              # counting flags are integers
names = options.array("<name>")
shout = options.bool("--shout")
quiet = options.string?("--output")    # nil when not given
```

The same questions work on `ConfigOptions` from the configuration
layer (after precedence) and on a dispatch command's `options`. Note
that counting flags (`-vv`) are `Int32`, not `Bool`.

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

Dispatch also composes with the configuration layer:
`require "docopt/dispatch_config"` adds `Dispatch.config_main`, which
resolves every command's options through the full precedence chain
(CLI > environment > config file > docopt defaults) before `run` sees
them — commands keep reading `options["-p"]` unchanged — and supports
a per-command `--print-config` flag:

```crystal
exit(Docopt::Dispatch.config_main("say", ARGV,
  config_file_path: "~/.config/say/config.yml",
  env_prefix: "SAY",
  print_config_option: "--print-config"))
```

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

Options that take an argument have their own custom completions, keyed
by the option name: after `--speed ` (or `--speed=`) the values are
offered, and in bash the attached form completes `--speed=5`-style
words.

```crystal
completions = {"--speed" => "5 10 15 20"}
```

Without a custom, the value of an option with an argument completes
with file names.

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

## Man Pages

If the doc is the single source of truth, it is also the manual:
`Docopt.man_page` turns it into a roff page — the description becomes
NAME and DESCRIPTION, the usage section SYNOPSIS, the declared options
OPTIONS with their defaults.

```crystal
puts Docopt.man_page("naval_fate", doc, version: VERSION)
```

A typical wiring is a `--man` flag writing it to stdout, or an
install target putting it in `share/man/man1`. The output is
deterministic; dates and versions come only from what you pass.

## Colored Help

Help and usage output can be colored through a hook: set
`Docopt.colorizer` to any `Proc(String, String)` and it runs on help
text and usage-in-errors — only on terminals, and only when
`NO_COLOR` (https://no-color.org) is unset. `Docopt.colorize(text,
io)` applies the same gating to your own output.

For tartrazine-grade coloring, tartrazine itself ships the
integration — its docopt lexer highlights the help, in-process:

```crystal
require "docopt"
require "tartrazine/docopt_color"   # from the tartrazine shard

Docopt.use_tartrazine_color            # or use_tartrazine_color("gruvbox-dark")
options = Docopt.docopt(doc, ARGV)
```

Applications that only want the docopt highlighting can bake just
that lexer into their binary: build with `-Dnolexers` and
`TT_LEXERS=docopt` in the compiler's environment.

## Examples

Both are built by `shards build` and installed in CI; see
`examples/README.md`.

### Naval Fate CLI

The classic docopt example, with completion generation for the three
shells and custom completions with dynamic content:

```bash
./bin/naval_fate --help
./bin/naval_fate --completion-bash > ~/.bash_completion.d/naval_fate
```

### say

A subcommand-oriented tool built from the dispatch and completion
layers: each command carries its own doc, and one completion script
covers the whole tree:

```bash
./bin/say help
./bin/say hello --shout -p mars
./bin/say --completion-bash
```

## Development

```bash
shards build  # Builds both examples
crystal spec  # 353 examples: unit, reference, conformance and real-shell completion tests
ameba         # Lint
```

The spec suite runs the official docopt conformance cases
(`spec/fixtures/testcases.docopt`), a port of the reference unit
tests, and executes generated completion scripts through real bash
(fish and zsh when installed).

## Contributing

1. Fork it ( https://github.com/ralsina/docopt.cr/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes using conventional commit messages (feat:, fix:, chore:, ...) — the changelog is generated from them
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [chenkovsky](https://github.com/chenkovsky) chenkovsky.chen - creator, maintainer
- [ralsina](https://github.com/ralsina) Roberto Alsina - fork maintainer
