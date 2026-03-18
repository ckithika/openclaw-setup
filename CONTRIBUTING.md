# Contributing

Thanks for your interest in contributing to openclaw-setup.

## How to Contribute

1. **Open an issue first** to discuss your change.
2. **Fork and branch** from `main`.
3. **Test your changes** (see below).
4. **Submit a PR** referencing the issue.

## Development

### Prerequisites

- Bash 3.2+ (macOS default)
- [ShellCheck](https://www.shellcheck.net/) for linting: `brew install shellcheck`

### Testing

```bash
# Syntax check
bash -n setup.sh

# Lint
shellcheck setup.sh

# Dry run (native mode, minimal)
printf '%s\n' "1" "test" $(printf '%.0s""' {1..26}) "y" "n" "n" "n" "n" "n" "n" "1" "1" "n" "n" "n" "n" | bash setup.sh
```

### Code Guidelines

- **Bash 3.2 compatible** — no `${var,,}` (use `tr`), no associative arrays
- **All `read` calls** must have `|| true` to handle EOF
- **No `[[ ]] && command`** on its own line — use `if/then/fi` instead (`set -e` safe)
- **All user input** must go through `validate_*` functions
- **Secrets** must use `ask_secret` (hidden input) and `chmod 600`
- **New features** should be toggleable where possible
- **Keep functions focused** — single responsibility

### File Structure

```
setup.sh            # Main script (single file by design)
README.md           # User-facing docs
CHANGELOG.md        # Version history (Keep a Changelog format)
CONTRIBUTING.md     # This file
LICENSE             # MIT
.github/
  workflows/ci.yml  # ShellCheck + syntax check
```

## Reporting Bugs

Include:
- OS and version (`sw_vers` or `lsb_release -a`)
- Bash version (`bash --version`)
- Error output
- Steps to reproduce
- Deploy mode (native/docker) and which features were enabled
