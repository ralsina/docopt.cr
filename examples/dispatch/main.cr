#!/usr/bin/env crystal

# A subcommand-oriented tool built from docopt.cr's dispatch and
# completion layers. Each command carries its own docopt help text;
# the shell completion scripts cover the whole command tree.

require "../../src/docopt/dispatch"

struct Hello < Docopt::Dispatch::Command
  @@name = "hello"
  @@doc = <<-HELP
    Says hello to the world

    Usage:
      say hello [--shout] [-p PLANET]

    Options:
      --shout     Say it louder
      -p PLANET   Planet to greet [default: world]
    HELP

  def run : Int32
    greeting = "hello #{options["-p"]}"
    puts(options["--shout"] ? greeting.upcase : greeting)
    0
  end
end

struct Bye < Docopt::Dispatch::Command
  @@name = "bye"
  @@doc = <<-HELP
    Says goodbye

    Usage:
      say bye [--soon]

    Options:
      --soon  Come back soon
    HELP

  def run : Int32
    puts(options["--soon"] ? "bye, come back soon" : "bye")
    0
  end
end

Hello.register
Bye.register

# Completion flags are handled before dispatch: they print a script
# for the current shell covering every registered command.
completion_scripts = {
  "--completion-bash" => -> { puts Docopt::Dispatch.bash_completion("say") },
  "--completion-fish" => -> { puts Docopt::Dispatch.fish_completion("say") },
  "--completion-zsh"  => -> { puts Docopt::Dispatch.zsh_completion("say") },
}
if ARGV.size == 1 && (generator = completion_scripts[ARGV[0]?]?)
  generator.call
  exit 0
end

exit Docopt::Dispatch.main("say", ARGV)
