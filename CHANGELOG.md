# Changelog

All notable changes to this project are documented in this file.
## Unreleased

### Miscellaneous
- Docs: read the README end to end and fix what grew stale

## 1.0.0 - 2026-09-27

### Miscellaneous
- Docs: badges, changelog and a README that tells the whole story

## 0.9.0 - 2026-09-27

### Features
- Feat: dispatch meets configuration via Dispatch.config_main

## 0.8.0 - 2026-09-27

### Features
- Feat: make the typo suggestions reusable as Dispatch.suggestions_for

## 0.7.0 - 2026-09-27

### Features
- Feat: subcommand-aware completion from the dispatch registry

## 0.6.0 - 2026-09-27

### Features
- Feat: add the configuration and dispatch layers as optional requires

## 0.5.0 - 2026-09-27

### Bug Fixes
- Fix: pass the official docopt conformance suite
- Fix: generate working completion scripts for bash, fish and zsh

### Features
- Feat: formalize the Compiled pattern as the contract for layered tools

### Miscellaneous
- Chore: remove committed binaries and local agent settings
- Style: fix remaining ameba findings
- Ci: replace Travis with GitHub Actions
- Chore: ignore lib/ where shards installs dependencies
- Chore: bump version to 0.5.0

## 0.4.0 - 2026-09-24

### Features
- Feat: parse usage texts at compile time with Docopt.compile

### Miscellaneous
- Merge pull request #3 from ralsina/feature/compile-time-parse
- Bump version to 0.4.0

## 0.3.1 - 2025-11-20

### Bug Fixes
- Fix custom completions for options with arguments

### Miscellaneous
- Bump version to 0.3.1

## 0.3.0 - 2025-11-19

### Bug Fixes
- Fix bug.
- Fixing crystal syntax (default args)
- Fixing heredoc in README
- Fixed typo in method name.
- Fix: remove color escape sequences before parsing
- Fix failing tests for shell completion custom completions

### Miscellaneous
- Init commit
- Remove debug
- Remove debug command
- Update document
- Merge pull request #1 from nuxlli/feature/updating_crystal
- Refactoring tests and improving api
- Adding raise exception test
- Merge pull request #2 from nuxlli/feature/improving_parse_and_api
- Update mail
- Update shard name
- Modify readme
- Crystal 0.16.0
- Upgrading crystal 0.15.0
- Merge pull request #3 from nuxlli/master
- Merge branch 'master' of https://github.com/chenkovsky/docopt.cr
- Remove deprecated syntax 'as'
- Make crystal-0.19.x happy
- Make compiler happy
- Refine doc
- Correct typos in Exception class names.
- Merge pull request #6 from rhass/master
- Merge pull request #7 from yb66/inspect-typo-fix
- Reflects version in shard
- Merge pull request #8 from noraj/patch-1
- Use delegate instead of inheriting Array(String)
- Chore: make ameba ignore current issues
- Chore: added myself to shard.yml
- Chore: updated README
- Chore: added TODO
- Dummy code
- Add license for shell completion code
- Reimplemented the bash completion from infi.docopt_completions
- Remove dead code
- Expanded README
- Add Fish and ZSH completion support to docopt.cr
- Add comprehensive naval_fate example with working shell completions
- Merge pull request #1 from ralsina/feature/fish-zsh-completion
- Release v0.3.0: Add comprehensive shell completion support

