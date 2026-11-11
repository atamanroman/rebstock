_default:
    @just --list

# Start a devserver on localhost:3000 that watches for changes (--clean to wipe ./data)
dev *args:
    #!/usr/bin/env sh
    for arg in {{args}}; do
        case "$arg" in
            --clean) rm -rf ./data && echo "Cleaned ./data" ;;
            --empty) rm -rf ./data && echo "Cleaned ./data" ;;
        esac
    done
    watchexec --restart --exts gleam,css -- just _dev

_dev:
    gleam dev

# Run tests
test:
    gleam test

# Run tests with code coverage report
cover:
    gleam build && erl -pa build/dev/erlang/*/ebin -noshell -eval "coverage_ffi:run_with_coverage()"

# Build everything
build:
    gleam build

# Lint the Gleam code
lint:
    gleam format --check .
    gleam build --warnings-as-errors

# Format the Gleam code
format:
    gleam format .

# Run the project site locally
site-dev:
    cd site && zola serve --drafts

# Build the project site; optionally override its base URL
site-build base_url="":
    cd site && zola build {{ if base_url == "" { "" } else { "--base-url=" + base_url } }}

# Validate the project site and its links
site-check:
    cd site && zola check

# Build and publish the project site to Cloudflare
site-deploy: (site-build "https://rebstock.atamanroman.dev")
    cd site && npx wrangler deploy

# Check if all dev tools are available and install Git pre-commit lint hook
setup-dev:
    @echo "Check available dev tools"
    @type gleam > /dev/null 2>&1 && printf 'gleam\t\t\t\t[✓]\n' || printf 'gleam\t\t\t\t[-]\n'
    @type npm > /dev/null 2>&1 && printf 'npm\t\t\t\t[✓]\n' || printf 'npm\t\t\t\t[-]\n'
    @type lefthook > /dev/null 2>&1 && printf 'lefthook*\t\t\t[✓]\n' || printf 'lefthook*\t\t\t[-]\n'
    @type watchexec > /dev/null 2>&1 && printf 'watchexec*\t\t\t[✓]\n' || printf 'watchexec*\t\t\t[-]\n'
    @type nix > /dev/null 2>&1 && printf 'nix** \t\t\t\t[✓]\n' || printf 'nix** \t\t\t\t[-]\n'
    @echo "---"
    @echo "* = dev only, ** = optional"
    @echo
    @echo "Install pre-commit hook"
    @type lefthook > /dev/null 2>&1 && lefthook install || echo "lefthook is not installed!"
    @echo
    @echo "Install browser/MCP test dependencies (not needed to build the app)"
    @type npm > /dev/null 2>&1 && npm ci || echo 'npm is not installed!'
