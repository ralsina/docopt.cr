# Conformance suite for the docopt language, run against the official
# language-agnostic test cases from the reference implementation:
#
#   https://github.com/docopt/docopt/blob/master/testcases.docopt
#
# The fixture format (parsed the same way as the docopt.go conformance
# runner): cases are separated by `r"""`; everything up to `"""` is the
# doc, then each `$ prog <argv...>` line is followed by the expected
# result — either a JSON object of option values or the string
# "user-error" meaning a DocoptExit is expected. `#`-comments are
# stripped from the whole file first.

require "./spec_helper"
require "json"

FIXTURE = "#{__DIR__}/fixtures/testcases.docopt"

record ConformanceCase,
  id : Int32,
  doc : String,
  prog : String,
  argv : Array(String),
  user_error : Bool,
  expected : Hash(String, (String | Int32 | Bool | Array(String))?)?

def parse_testcases(raw : String)
  cases = [] of ConformanceCase
  id = 0

  # Comments are stripped globally, like in the reference runner.
  stripped = raw.gsub(/#.*/, "").strip
  fixtures = stripped.starts_with?("\"\"\"") ? [""] + stripped.split("r\"\"\"") : stripped.split("r\"\"\"")

  fixtures.each do |fixture|
    doc, _, body = fixture.partition("\"\"\"")
    next if body.strip.empty?

    body.split("$")[1..].each do |test|
      argv_line, _, expectation = test.strip.partition("\n")
      prog, _, argv_string = argv_line.strip.partition(" ")
      argv = argv_string.empty? ? [] of String : argv_string.split

      parsed = JSON.parse(expectation)
      id += 1
      if (message = parsed.as_s?) && message == "user-error"
        cases << ConformanceCase.new(id, doc, prog, argv, true, nil)
      else
        expected = Hash(String, (String | Int32 | Bool | Array(String))?).new
        parsed.as_h.each do |key, value|
          expected[key] = conformance_value(value)
        end
        cases << ConformanceCase.new(id, doc, prog, argv, false, expected)
      end
    end
  end
  cases
end

def conformance_value(value : JSON::Any) : (String | Int32 | Bool | Array(String))?
  case raw = value.raw
  when String  then raw
  when Bool    then raw
  when Int64   then raw.to_i32
  when Float64 then raw.to_i32
  when Nil     then nil
  when Array(JSON::Any)
    raw.map(&.as_s)
  else
    raise "unexpected expectation type: #{value.inspect}"
  end
end

describe "docopt conformance suite" do
  parse_testcases(File.read(FIXTURE)).each do |test_case|
    it "case #{test_case.id}: #{test_case.prog} #{test_case.argv.join(' ')}" do
      if test_case.user_error
        expect_raises(Docopt::DocoptExit) do
          Docopt.docopt(test_case.doc, test_case.argv, help: false, exit: false)
        end
      else
        result = Docopt.docopt(test_case.doc, test_case.argv, help: false, exit: false)
        result.should eq(test_case.expected)
      end
    end
  end
end
