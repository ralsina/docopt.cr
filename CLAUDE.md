# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is **docopt.cr**, a Crystal language implementation of the docopt command-line interface parsing library. The library parses command-line arguments based on a usage pattern that is naturally expressed in the help message itself.

## Build Commands

```bash
# Build the library
crystal build src/docopt.cr

# Run tests
crystal spec

# Run linter and fix issues automatically
ameba --fix

# Install dependencies
shards install
```

## Architecture

The library is organized around a pattern-matching parser that converts docopt usage patterns into a tree of Pattern objects:

### Core Classes (src/docopt.cr)

- **Pattern**: Abstract base class for all pattern elements
- **LeafPattern**: Base for leaf nodes (Argument, Command, Option)
- **BranchPattern**: Base for container nodes (Required, Optional, Either, OneOrMore)
- **Tokens**: Tokenizer for parsing usage patterns and command-line arguments

### Key Pattern Types:
- **Argument**: Positional arguments (`<name>`)
- **Command**: Subcommands (verb-like tokens)
- **Option**: Command-line options (`-h`, `--help`, `--speed=<kn>`)
- **Required**: Required sequence of patterns `(pattern)`
- **Optional**: Optional sequence of patterns `[pattern]`
- **Either**: Alternative patterns `pattern | pattern`
- **OneOrMore**: Repeated patterns `pattern...`

### Main API:
- `Docopt.docopt(doc, argv, help, version, options_first, exit)`: Main entry point that parses arguments and returns a Hash

### Parsing Process:
1. Parse usage patterns from doc string
2. Parse default options from options section
3. Build pattern tree and fix identities/repeating arguments
4. Parse command-line argv into patterns
5. Match patterns and extract values into result hash

## Important Implementation Notes

- Uses delegation pattern for Tokens class instead of inheriting from Array(String)
- Pattern matching is recursive and backtracking
- Options with arguments can have default values specified in [default: value]
- Supports both short (-h) and long (--help) option forms
- Handles repeatable options and arguments using Array(String) for values
- Commands accumulate as Int32 counters when repeated

## Testing

The test suite in `spec/docopt_spec.cr` covers:
- Subcommand and option matching
- Repeatable options and arguments
- Alias options with default values
- Error handling for invalid patterns

Run tests with `crystal spec` to verify functionality.