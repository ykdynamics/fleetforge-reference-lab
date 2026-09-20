# FleetForge Reference Lab — operator entry point.
#
# The remaining lab targets (provisioning, protocol stacks, FleetForge integration,
# exercises, reset) are specified in docs/command-contract.md and are NOT implemented
# yet. A target appears here when it does the work described in that contract. This
# repository does not ship targets that exit 0 while doing nothing.

INVENTORY ?=
HOST ?=
ROLE ?=

.DEFAULT_GOAL := help
.PHONY: help check check-links check-examples test-preflight preflight

help: ## What this repository can actually run today
	@echo 'FleetForge Reference Lab'
	@echo
	@echo 'Implemented targets:'
	@awk 'BEGIN {FS = ":.*## "} /^[a-z][a-z-]*:.*## / {printf "  %-16s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo 'Remaining lab targets (provisioning, stacks, integration, exercises,'
	@echo 'reset) are specified but NOT implemented. See docs/command-contract.md.'
	@echo 'Start here: README.md and docs/walkthrough/README.md'

check: check-links check-examples ## Run every repository check

check-links: ## Verify every relative Markdown link resolves to a file
	@./scripts/check-links.sh

check-examples: ## Verify every *.example.yml parses as YAML
	@./scripts/check-examples.sh

test-preflight: ## Exercise the preflight checks in a container (needs docker; simulated, not hardware)
	@./scripts/test-preflight.sh

preflight: ## Read-only gateway preflight (HOST= ROLE=zigbee|zwave [INVENTORY=])
	@./scripts/preflight.sh "$(HOST)" "$(ROLE)" "$(INVENTORY)"
