.PHONY: lint test logo website website-serve help

logo: ## Redraw doc/img from scripts/gen-logo.py (requires Python and Pillow)
	python3 ./scripts/gen-logo.py

lint: ## Run ShellCheck over the install script and its tests
	shellcheck -x scripts/install.sh scripts/version_test.sh

test: ## Run the install script's helper tests
	bash scripts/version_test.sh

website: ## Build the documentation website into website/public (requires hugo)
	cd website && hugo --gc --minify --cleanDestinationDir

website-serve: ## Serve the documentation website locally with live reload
	cd website && hugo server

.DEFAULT_GOAL := help
help:
	@grep -E '^[0-9a-zA-Z_-]+[[:blank:]]*:.*?## .*$$' $(MAKEFILE_LIST) | sort \
	| awk 'BEGIN {FS = ":.*?## "}; {printf "\033[1;32m%-15s\033[0m %s\n", $$1, $$2}'
