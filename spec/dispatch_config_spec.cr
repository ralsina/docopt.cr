require "./spec_helper"
require "../src/docopt/dispatch_config"

CONFIG_DOC = <<-HELP
  Greets people

  Usage:
    spec cgreet [--shout] [-p PLANET]

  Options:
    --shout     Shout it
    -p PLANET   Planet [default: world]
  HELP

struct ConfigCmdGreet < Docopt::Dispatch::Command
  @@name = "cgreet"
  @@doc = CONFIG_DOC
  class_property last_planet : String = ""

  def run : Int32
    @@last_planet = options["-p"].as(String)
    0
  end
end

struct ConfigCmdShout < Docopt::Dispatch::Command
  @@name = "cshout"
  @@doc = <<-HELP
    Shouts

    Usage:
      spec cshout [--times=<n>]

    Options:
      --times=<n>  How many times [default: 2]
    HELP

  def run : Int32
    0
  end
end

ConfigCmdGreet.register
ConfigCmdShout.register

def run_config_main(arguments : Array(String), config_file : String? = nil, env_prefix : String? = "SPECTOOL")
  stdout_io = IO::Memory.new
  stderr_io = IO::Memory.new
  code = Docopt::Dispatch.config_main("spec", arguments,
    config_file_path: config_file, env_prefix: env_prefix,
    stdout: stdout_io, stderr: stderr_io)
  {code, stdout_io.to_s, stderr_io.to_s}
end

describe "Docopt::Dispatch.config_main" do
  it "runs commands with doc defaults resolved" do
    code, _stdout, stderr = run_config_main(["cgreet"])
    code.should eq 0
    stderr.should be_empty
    ConfigCmdGreet.last_planet.should eq "world"
  end

  it "lets the config file override doc defaults" do
    Dir.tempdir.tap do |dir|
      config = File.join(dir, "docopt-dispatch-config-#{Random::Secure.hex(4)}.yml")
      File.write(config, "p: mars\n")
      begin
        code, _stdout, _stderr = run_config_main(["cgreet"], config_file: config)
        code.should eq 0
        ConfigCmdGreet.last_planet.should eq "mars"
      ensure
        File.delete(config)
      end
    end
  end

  it "lets the environment override the config file" do
    Dir.tempdir.tap do |dir|
      config = File.join(dir, "docopt-dispatch-env-#{Random::Secure.hex(4)}.yml")
      File.write(config, "p: venus\n")
      ENV["SPECTOOL_P"] = "jupiter"
      begin
        code, _stdout, _stderr = run_config_main(["cgreet"], config_file: config)
        code.should eq 0
        ConfigCmdGreet.last_planet.should eq "jupiter"
      ensure
        ENV.delete("SPECTOOL_P")
        File.delete(config)
      end
    end
  end

  it "lets CLI arguments win over everything" do
    ENV["SPECTOOL_P"] = "jupiter"
    begin
      code, _stdout, _stderr = run_config_main(["cgreet", "-p", "pluto"])
      code.should eq 0
      ConfigCmdGreet.last_planet.should eq "pluto"
    ensure
      ENV.delete("SPECTOOL_P")
    end
  end

  it "normalizes config-file numbers to docopt types" do
    Dir.tempdir.tap do |dir|
      config = File.join(dir, "docopt-dispatch-numbers-#{Random::Secure.hex(4)}.yml")
      File.write(config, "times: 3\n")
      begin
        # runs without raising: --times resolves to Int32 3
        code, _stdout, _stderr = run_config_main(["cshout"], config_file: config)
        code.should eq 0
      ensure
        File.delete(config)
      end
    end
  end

  it "prints a command's resolved configuration on request" do
    ENV["SPECTOOL_P"] = "mars"
    stdout_io = IO::Memory.new
    stderr_io = IO::Memory.new
    begin
      code = Docopt::Dispatch.config_main("spec", ["cgreet", "--print-config"],
        env_prefix: "SPECTOOL", print_config_option: "--print-config",
        stdout: stdout_io, stderr: stderr_io)
      stdout = stdout_io.to_s
      code.should eq 0
      stdout.should contain "p: mars"
      # flags that no tier sets are omitted: absent means false
      stdout.should_not contain "shout"
    ensure
      ENV.delete("SPECTOOL_P")
    end
  end

  it "keeps dispatch's help and error behavior" do
    code, stdout, _stderr = run_config_main([] of String)
    code.should eq 0
    stdout.should contain "Usage:"

    code, stdout, _stderr = run_config_main(["cgreet", "--help"])
    code.should eq 0
    stdout.should contain "Greets people"

    code, _stdout, stderr = run_config_main(["bogus"])
    code.should eq 1
    stderr.should contain "is not a spec command"

    code, _stdout, stderr = run_config_main(["cgreet", "-x"])
    code.should eq 1
    stderr.should contain "Usage:"
    stderr.should contain "See 'spec help cgreet'"
  end
end
