# FleetForge Reference Lab — operator entry point.
#
# Today this Makefile implements only the repository's own checks. The lab targets
# (provisioning, protocol stacks, FleetForge integration, exercises, reset) are
# specified in docs/command-contract.md and are NOT implemented yet.
#
# A target appears here when it does the work described in that contract. This
# repository does not ship targets that exit 0 while doing nothing.

.DEFAULT_GOAL := help
.PHONY: help check check-links check-examples

help: ## What this repository can actually run today
	@echo 'FleetForge Reference Lab'
	@echo
	@echo 'Implemented targets:'
	@awk 'BEGIN {FS = ":.*## "} /^[a-z][a-z-]*:.*## / {printf "  %-16s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo 'Lab targets (provisioning, stacks, integration, exercises, reset) are'
	@echo 'specified but NOT implemented. See docs/command-contract.md.'
	@echo 'Start here: README.md and docs/walkthrough/README.md'

check: check-links check-examples ## Run every repository check

check-links: ## Verify every relative Markdown link resolves to a file
	@./scripts/check-links.sh

check-examples: ## Verify every *.example.yml parses as YAML
	@./scripts/check-examples.sh
