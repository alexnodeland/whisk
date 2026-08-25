# Whisk — task runner (primary). A thin Makefile mirrors these for muscle memory.
# Run `just` (or `just --list`) to see all recipes.

set shell := ["bash", "-uc"]

# Show available recipes
default:
    @just --list

# Dev build (arm64, fast) → build/Whisk.app
build:
    ./build.sh

# Release build (universal binary + ZIP); pass a version like: just release v1.0.0
release version="":
    ./build.sh --release {{ if version != "" { "--version " + version } else { "" } }}

# Run unit tests
test:
    ./test.sh

# Run tests AND enforce the hard 100% coverage gate on the logic layer
coverage:
    ./test.sh --coverage
    python3 scripts/coverage-gate.py .build-tests/cov/cov.json

# Run the integration tests against the real filesystem (temp dirs, --sweep-once)
integration:
    ./scripts/integration-test.sh

# End-to-end: launch the built app and drive it over whisk:// (needs a GUI session)
smoke: build
    ./scripts/smoke-test.sh

# Audit the I/O shims for logic that belongs in the covered core
shim-audit:
    python3 scripts/shim-audit.py

# Lint with SwiftLint (strict)
lint:
    swiftlint lint --strict Sources/ Tests/

# Auto-format with swift-format
fmt:
    swift-format format --in-place --recursive Sources/ Tests/

# Check formatting (fails if changes needed)
fmt-check:
    swift-format lint --strict --recursive Sources/ Tests/

# Full CI gate: lint + format + shim audit + tests + 100% coverage + integration
check: lint fmt-check shim-audit coverage integration

# Build and open the app
dev: build
    open ./build/Whisk.app

# Build and copy Whisk.app to /Applications
install: build
    cp -R ./build/Whisk.app /Applications/
    @echo "Installed to /Applications/Whisk.app"

# Remove build artifacts
clean:
    rm -rf build .build-tests

# One-time bootstrap: install tools (incl. just) and git hooks
setup:
    command -v just >/dev/null 2>&1 || brew install just
    brew bundle
    lefthook install
    @echo "Setup complete."
