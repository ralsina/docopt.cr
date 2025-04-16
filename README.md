# docopt.cr

docopt for crystal-lang

This is a fork of the original [docopt.cr by chenkovsky](https://github.com/chenkovsky/docopt.cr) with a few bugfixes.


It has a couple of bugfixes and I am now starting to add new features:

* bash completion generation
* Custom hooks for smarter completion
* zsh completion generation [TBD]
* fish completion generation [TBD]


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

docopt.cr can generate shell completion scripts for bash (other shells to come)
so that when you `TAB` while writing a command it will show you the possible
options.

The code to create a bash completion looks like this for the classic 
`naval_fate` example:

```crystal
    bash_completion = Docopt.bash_completion("naval_fate", doc)
```

This will give you a reasonable bash completion. To make this available to the user
you could have something like a `naval_fate --completion` in your usage instructions
and either tell the user to put this in their `.bashrc`:

```bash
    naval_fate --completion >> ~/.bashrc
```

Or write it to a file and put it in /etc/bash_completion.d/:

```bash
    naval_fate --completion > /etc/bash_completion.d/naval_fate
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

## Development

TODO: Write development instructions here

## Contributing

1. Fork it ( https://github.com/ralsina/docopt.cr/fork )
2. Create your feature branch (git checkout -b my-new-feature)
3. Commit your changes (git commit -am 'Add some feature')
4. Push to the branch (git push origin my-new-feature)
5. Create a new Pull Request

## Contributors

- [chenkovsky](https://github.com/chenkovsky) chenkovsky.chen - creator, maintainer
- [ralsina](https://github.com/ralsina) Roberto Alsina - fork maintainer
