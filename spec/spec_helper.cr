require "spec"
require "file_utils"
require "../src/docopt.cr"
require "../src/bash_completion.cr"

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
