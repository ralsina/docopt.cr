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
