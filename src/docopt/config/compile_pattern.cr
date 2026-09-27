# Compile-time helper for `Docopt.compile_config`: parses the usage
# text given as the first argument and prints Crystal source that
# rebuilds a ConfigCompiled. Run by the compiler through the `run`
# macro.
require "../../docopt"

doc = ARGV[0]?
unless doc
  STDERR.puts "Docopt.compile_config: no usage text given"
  exit 1
end

begin
  puts "Docopt::ConfigCompiled.new(\n#{Docopt.parse(doc).to_crystal}\n)"
rescue ex : Docopt::DocoptException
  STDERR.puts "Docopt.compile_config: invalid usage text: #{ex.message}"
  exit 1
end
