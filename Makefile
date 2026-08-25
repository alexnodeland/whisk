# Thin mirror of the justfile (see ADR 0002). `just` is the primary runner;
# this exists for muscle memory. Targets delegate to the same scripts.
.PHONY: build release test coverage integration smoke shim-audit lint format format-check check clean install setup dev help

help: ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

build: ## Dev build (arm64, fast)
	@./build.sh

release: ## Release build (universal binary + ZIP)
	@./build.sh --release

test: ## Run unit tests
	@./test.sh

coverage: ## Run tests + enforce the hard 100% coverage gate
	@./test.sh --coverage
	@python3 scripts/coverage-gate.py .build-tests/cov/cov.json

integration: ## Run integration tests against the real filesystem
	@./scripts/integration-test.sh

smoke: build ## End-to-end: drive the built app over whisk:// (needs a GUI session)
	@./scripts/smoke-test.sh

shim-audit: ## Audit the I/O shims for logic that belongs in the core
	@python3 scripts/shim-audit.py

lint: ## Run SwiftLint (strict)
	@swiftlint lint --strict Sources/ Tests/

format: ## Auto-format with swift-format
	@swift-format format --in-place --recursive Sources/ Tests/

format-check: ## Check formatting (fails if changes needed)
	@swift-format lint --strict --recursive Sources/ Tests/

check: lint format-check shim-audit coverage integration ## Full CI gate

clean: ## Remove build artifacts
	@rm -rf build .build-tests

setup: ## Install tools and git hooks (one-time bootstrap)
	@command -v just >/dev/null 2>&1 || brew install just
	@brew bundle
	@lefthook install
	@echo "Setup complete."

dev: build ## Build and open the app
	@open ./build/Whisk.app

install: build ## Build and copy Whisk.app to /Applications
	@cp -R build/Whisk.app /Applications/
	@echo "Installed to /Applications/Whisk.app"
