#!/usr/bin/env crystal

require "../src/docopt"

# Naval Fate CLI Application with Shell Completion Support
# This is a demonstration of docopt.cr with shell completion generation

DOC = <<-DOC
Naval Fate - Command your fleet with style!

Usage:
  naval_fate ship new <name>...
  naval_fate ship <name> move <x> <y> [--speed=<kn>]
  naval_fate ship shoot <x> <y>
  naval_fate ship list
  naval_fate mine (set|remove) <x> <y> [--moored|--drifting]
  naval_fate mine list
  naval_fate fleet status
  naval_fate save [--files=files...]
  naval_fate set_speed [--speed=<kn>]
  naval_fate set_alert [--level=<level>]
  naval_fate --completion-bash
  naval_fate --completion-fish
  naval_fate --completion-zsh
  naval_fate -h | --help
  naval_fate --version

Options:
  -h --help           Show this screen.
  --version           Show version.
  -s,--speed=<kn>     Speed in knots [default: 10].
  --moored            Moored (anchored) mine.
  --drifting          Drifting mine.
  --files=<files>     List of files to save.
  --level=<level>     Alert level [default: normal].
  --completion-bash   Generate bash completion script.
  --completion-fish   Generate fish completion script.
  --completion-zsh    Generate zsh completion script.

Examples:
  naval_fate ship new "USS Enterprise" "USS Constitution"
  naval_fate ship "USS Enterprise" move 10 20 --speed=15
  naval_fate ship "USS Enterprise" shoot 30 40
  naval_fate mine set 50 60 --moored
  naval_fate fleet status
DOC

# Version information
VERSION = "1.0.0"

# Simple ship database
class ShipDatabase
  SHIPS = [
    "USS Enterprise",
    "USS Constitution",
    "USS Missouri",
    "USS Arizona",
    "HMS Victory",
    "HMS Bounty",
    "Bismarck",
    "Titanic",
    "Queen Mary",
    "Lusitania"
  ]

  def self.list_ships : String
    SHIPS.join(" ")
  end

  def self.add_ship(name : String) : Bool
    SHIPS << name unless SHIPS.includes?(name)
    true
  end

  def self.ship_exists?(name : String) : Bool
    SHIPS.includes?(name)
  end
end

# Mine tracking
class MineTracker
  MINES = [] of NamedTuple(x: Int32, y: Int32, type: String)

  def self.add_mine(x : Int32, y : Int32, type : String)
    MINES << {x: x, y: y, type: type}
  end

  def self.remove_mine(x : Int32, y : Int32) : Bool
    MINES.reject! { |mine| mine[:x] == x && mine[:y] == y }
    true
  end

  def self.list_mines : String
    MINES.map { |m| "#{m[:x]}:#{m[:y]}(#{m[:type]})" }.join(" ")
  end
end

# Custom completions for shell integration
CUSTOM_COMPLETIONS = {
  "naval_fate_ship_new"      => ShipDatabase.list_ships,
  "naval_fate_ship"          => ShipDatabase.list_ships,
  "naval_fate_mine_set"      => "$(echo '10 20 30 40 50 60')",
  "naval_fate_mine_remove"   => MineTracker.list_mines,
  "naval_fate_files"         => "$(ls *.txt *.md 2>/dev/null || echo 'config.txt log.md')",
  # Option-level custom completions
  "--speed"                  => "5 10 15 20 25 30",
  "--level"                  => "low normal high critical",
  "-s"                       => "5 10 15 20 25 30"
}

# Main application logic
def run_naval_fate(args = ARGV)
  begin
    arguments = Docopt.docopt(DOC, args, help: true, version: VERSION)

    # Handle completion generation
    if arguments["--completion-bash"]?
      puts Docopt.bash_completion("naval_fate", DOC, CUSTOM_COMPLETIONS)
      exit 0
    elsif arguments["--completion-fish"]?
      puts Docopt.fish_completion("naval_fate", DOC, CUSTOM_COMPLETIONS)
      exit 0
    elsif arguments["--completion-zsh"]?
      puts Docopt.zsh_completion("naval_fate", DOC, CUSTOM_COMPLETIONS)
      exit 0
    end

    # Ship commands
    if arguments["ship"]?
      if arguments["new"]?
        names = arguments["<name>"].as(Array(String))
        names.each do |name|
          ShipDatabase.add_ship(name)
          puts "✓ Created ship: #{name}"
        end
        puts "🚢 Fleet now has #{ShipDatabase::SHIPS.size} ships"

      elsif arguments["move"]?
        ship_name = arguments["<name>"].as(String)
        x = arguments["<x>"].as(String)
        y = arguments["<y>"].as(String)
        speed = arguments["--speed"]? || "10"

        if ShipDatabase.ship_exists?(ship_name)
          puts "⚓ Moving #{ship_name} to coordinates (#{x}, #{y}) at #{speed} knots"
        else
          puts "❌ Ship '#{ship_name}' not found. Use 'naval_fate ship new' first."
        end

      elsif arguments["shoot"]?
        x = arguments["<x>"].as(String)
        y = arguments["<y>"].as(String)
        puts "💥 Firing cannons at coordinates (#{x}, #{y})"

      elsif arguments["list"]?
        puts "📋 Ships in fleet:"
        ShipDatabase::SHIPS.each_with_index do |ship, i|
          puts "  #{i + 1}. #{ship}"
        end
      end
    end

    # Mine commands
    if arguments["mine"]?
      if arguments["set"]?
        x = arguments["<x>"].as(Int32)
        y = arguments["<y>"].as(Int32)
        type = arguments["--moored"]? ? "moored" : "drifting"

        MineTracker.add_mine(x, y, type)
        puts "💣 Placed #{type} mine at (#{x}, #{y})"

      elsif arguments["remove"]?
        x = arguments["<x>"].as(Int32)
        y = arguments["<y>"].as(Int32)

        MineTracker.remove_mine(x, y)
        puts "🗑️  Removed mine at (#{x}, #{y})"

      elsif arguments["list"]?
        puts "💣 Mines deployed:"
        if MineTracker::MINES.empty?
          puts "  No mines deployed"
        else
          MineTracker::MINES.each_with_index do |mine, i|
            puts "  #{i + 1}. #{mine[:x]}:#{mine[:y]} (#{mine[:type]})"
          end
        end
      end
    end

    # Fleet status
    if arguments["fleet"]? && arguments["status"]?
      puts "🏴‍☠️ Fleet Status Report"
      puts "===================="
      puts "Ships: #{ShipDatabase::SHIPS.size}"
      puts "Mines: #{MineTracker::MINES.size}"
      puts "Status: Ready for battle! ⚔️"
    end

    # Save command
    if arguments["save"]?
      files = arguments["--files"]? ? arguments["--files"].as(Array(String)) : ["fleet_state.txt"]
      files.each do |file|
        puts "💾 Saving fleet state to #{file}"
        # In a real app, you'd actually save the state here
      end
    end

    # Set speed command
    if arguments["set_speed"]?
      speed = arguments["--speed"]? || "10"
      puts "⚡ Default fleet speed set to #{speed} knots"
    end

    # Set alert command
    if arguments["set_alert"]?
      level = arguments["--level"]? || "normal"
      puts "🚨 Alert level set to #{level}"
    end

  rescue Docopt::DocoptExit
    # Help/version was shown, just exit
    exit 0
  rescue ex
    puts "❌ Error: #{ex.message}"
    exit 1
  end
end

# Run the application if this file is executed directly
if PROGRAM_NAME.includes?("naval_fate")
  run_naval_fate
end