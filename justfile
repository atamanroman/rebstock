_default:
    @just --list

# Start a devserver on localhost:3000 that watches for changes in *.gleam and *.css files (--clean to wipe ./data)
dev *args:
    #!/usr/bin/env sh
    for arg in {{args}}; do
        case "$arg" in
            --clean) rm -rf ./data && echo "Cleaned ./data" ;;
        esac
    done
    watchexec --restart --exts gleam,css -- just _dev

_dev:
    tailwindcss -i src/css/app.css -o priv/static/css/app.css --content './src/**/*.gleam,./src/**/*.css'
    gleam dev

# Generate the minified tailwind CSS bundle
css:
    tailwindcss -i src/css/app.css -o priv/static/css/app.css --content './src/**/*.gleam,./src/**/*.css' --minify

# Run tests
test:
    gleam test

# Run tests with code coverage report
cover:
    gleam build && erl -pa build/dev/erlang/*/ebin -noshell -eval "coverage_ffi:run_with_coverage()"

# Build everything
build: css
    gleam build

# Lint the Gleam code
lint:
    gleam format --check .
    gleam build --warnings-as-errors

# Format the Gleam code
format:
    gleam format .

# Check if all dev tools are available and install Git pre-commit lint hook
setup-dev:
    @echo "Check available dev tools"
    @type gleam > /dev/null 2>&1 && printf 'gleam\t\t\t\t[✓]\n' || printf 'gleam\t\t\t\t[-]\n'
    @type tailwindcss > /dev/null 2>&1 && printf 'tailwindcss (standalone)\t[✓]\n' || printf 'tailwindcss (standalone)\t[-]\n'
    @type npm > /dev/null 2>&1 && printf 'npm\t\t\t\t[✓]\n' || printf 'npm\t\t\t\t[-]\n'
    @npm exec tailwindcss -- -h > /dev/null 2>&1 && printf 'tailwindcss (npm)\t\t[✓]\n' || printf 'tailwindcss (npm)\t\t[-]\n'
    @type lefthook > /dev/null 2>&1 && printf 'lefthook*\t\t\t[✓]\n' || printf 'lefthook*\t\t\t[-]\n'
    @type watchexec > /dev/null 2>&1 && printf 'watchexec*\t\t\t[✓]\n' || printf 'watchexec*\t\t\t[-]\n'
    @type nix > /dev/null 2>&1 && printf 'nix** \t\t\t\t[✓]\n' || printf 'nix** \t\t\t\t[-]\n'
    @echo "---"
    @echo "* = dev only, ** = optional"
    @echo
    @echo "Install pre-commit hook"
    @type lefthook > /dev/null 2>&1 && lefthook install || echo "lefthook is not installed!"
    @echo
    @echo "Install tailwindcss and @tailwindcss/cli"
    @type tailwindcss > /dev/null 2>&1 && echo 'tailwindcss standalone is available, skip `npm ci`' || (type npm > /dev/null 2>&1 && npm ci || echo 'npm is not installed!')
