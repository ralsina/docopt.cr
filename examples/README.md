# docopt.cr Examples

This directory contains example applications that demonstrate the shell completion functionality of docopt.cr.

## Naval Fate CLI

The `naval_fate` application is a comprehensive example that showcases:

- Multi-subcommand CLI structure
- Shell completion generation for Bash, Fish, and ZSH
- Custom completions with dynamic content
- Real-world usage patterns

### Building

```bash
# From the project root:
crystal build examples/naval_fate.cr -o examples/naval_fate
```

### Running Examples

```bash
# Show help
./examples/naval_fate --help

# Basic commands
./examples/naval_fate ship new "USS Enterprise"
./examples/naval_fate ship list
./examples/naval_fate fleet status

# Generate completion scripts
./examples/naval_fate --completion-bash > naval_fate_completion.bash
./examples/naval_fate --completion-fish > naval_fate_completion.fish
./examples/naval_fate --completion-zsh > naval_fate_completion.zsh
```

### Installing Completions

#### Bash

```bash
# Option 1: Add to .bashrc
./examples/naval_fate --completion-bash >> ~/.bashrc
source ~/.bashrc

# Option 2: System-wide
sudo ./examples/naval_fate --completion-bash > /etc/bash_completion.d/naval_fate
```

#### Fish

```bash
# User-specific
./examples/naval_fate --completion-fish > ~/.config/fish/completions/naval_fate.fish

# System-wide
sudo ./examples/naval_fate --completion-fish > /usr/share/fish/vendor_completions.d/naval_fate.fish
```

#### ZSH

```bash
# User-specific
./examples/naval_fate --completion-zsh > ~/.local/share/zsh/site-functions/_naval_fate

# System-wide
sudo ./examples/naval_fate --completion-zsh > /usr/share/zsh/site-functions/_naval_fate
```

### Testing Completions

After installing the completions for your shell, try these:

```bash
# Type these and press TAB to see completions:
naval_fate [TAB]
naval_fate ship [TAB]
naval_fate ship new [TAB]
naval_fate mine [TAB]
naval_fate ship "USS [TAB]
```

### Custom Completions

The example demonstrates custom completions:

- **Ship names**: `naval_fate ship new [TAB]` shows predefined ship names
- **Mine coordinates**: `naval_fate mine set [TAB]` shows coordinate suggestions
- **File lists**: `naval_fate save --files [TAB]` shows file suggestions

### Application Features

The naval_fate app includes:

- **Ship Management**: Create, list, move, and command ships
- **Mine Operations**: Place, remove, and track naval mines
- **Fleet Status**: View overall fleet information
- **Save/Load**: Persist fleet state to files
- **Custom Completions**: Dynamic completion suggestions

This example serves as a template for building real CLI applications with docopt.cr completion support.