# Compile-time helper for `Docopt.compile`: parses the usage text
# given as the first argument and prints Crystal source that rebuilds
# the parsed pattern. Run by the compiler through the `run` macro.
require "../docopt"

doc = ARGV[0]?
unless doc
  STDERR.puts "Docopt.compile: no usage text given"
  exit 1
end

begin
  puts Docopt.parse(doc).to_crystal
rescue ex : Docopt::DocoptException
  STDERR.puts "Docopt.compile: invalid usage text: #{ex.message}"
  exit 1
end
