# Contributing to openclaw-setup

Thanks for your interest in contributing.

## How to Contribute

1. **Open an issue first** — Describe what you want to change and why.
2. **Fork and branch** — Create a feature branch from `main`.
3. **Test your changes:**
   - Run `bash -n setup.sh` to check syntax
   - Do a dry run in both native and Docker modes
   - Test `--reconfigure` on an existing config
4. **Keep it simple** — This is a shell script. Avoid adding dependencies.
5. **Submit a PR** — Reference the issue number.

## Guidelines

- Bash 3.2 compatible (macOS default shell)
- All user input must go through validation functions
- Secrets must use `ask_secret` (hidden input) and `chmod 600`
- New features should be toggleable where possible
- Keep the interactive wizard flow logical and sequential
- Test on both macOS and Linux if possible

## Reporting Bugs

Include:
- OS and version
- Shell (`bash --version`)
- Error output
- Steps to reproduce
