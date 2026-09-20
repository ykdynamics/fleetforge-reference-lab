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
.PHONY: help check check-links check-examples test-preflight test-provision preflight provision-plan provision stack-config stack-up stack-status stack-logs stack-down radio-devices lamp-off lamp-on agent-plan agent-install agent-status radio-backup scenario-restore agent-remove protocol-data-reset host-reset

help: ## What this repository can actually run today
	@echo 'FleetForge Reference Lab'
	@echo
	@echo 'Implemented targets:'
	@awk 'BEGIN {FS = ":.*## "} /^[a-z][a-z-]*:.*## / {printf "  %-16s %s\n", $$1, $$2}' $(MAKEFILE_LIST)
	@echo
	@echo 'Remaining lab targets (protocol stacks, FleetForge integration,'
	@echo 'exercises, reset) are specified but NOT implemented.'
	@echo 'See docs/command-contract.md.'
	@echo 'Start here: README.md and docs/walkthrough/README.md'

check: check-links check-examples ## Run every repository check

check-links: ## Verify every relative Markdown link resolves to a file
	@./scripts/check-links.sh

check-examples: ## Verify every *.example.yml parses as YAML
	@./scripts/check-examples.sh

test-preflight: ## Exercise the preflight checks in a container (needs docker; simulated, not hardware)
	@./scripts/test-preflight.sh

test-provision: ## Exercise the provisioning guards locally (simulated, no gateway contacted)
	@./scripts/test-provision.sh

preflight: ## Read-only gateway preflight (HOST= ROLE=zigbee|zwave [INVENTORY=])
	@./scripts/preflight.sh "$(HOST)" "$(ROLE)" "$(INVENTORY)"

provision-plan: ## Show what provisioning would change, read-only (HOST= ROLE= [INVENTORY=])
	@MODE=plan ./scripts/provision.sh "$(HOST)" "$(ROLE)" "$(INVENTORY)"

provision: ## Provision one gateway — CHANGES THE HOST (HOST= ROLE= [INVENTORY=])
	@MODE=apply ./scripts/provision.sh "$(HOST)" "$(ROLE)" "$(INVENTORY)"

stack-config: ## Render and validate the protocol stack config (HOST= ROLE= [INVENTORY=])
	@ACTION=config ./scripts/stack.sh "$(HOST)" "$(ROLE)" "$(INVENTORY)"

stack-up: ## Deploy and start the protocol services (HOST= ROLE= [INVENTORY=])
	@ACTION=up ./scripts/stack.sh "$(HOST)" "$(ROLE)" "$(INVENTORY)"

stack-status: ## Service state, log bounds and broker reachability (HOST= ROLE= [INVENTORY=])
	@ACTION=status ./scripts/stack.sh "$(HOST)" "$(ROLE)" "$(INVENTORY)"

stack-logs: ## Tail the role's service logs (HOST= ROLE= [INVENTORY=])
	@ACTION=logs ./scripts/stack.sh "$(HOST)" "$(ROLE)" "$(INVENTORY)"

stack-down: ## Stop the services, keeping all data and pairings (HOST= ROLE= [INVENTORY=])
	@ACTION=down ./scripts/stack.sh "$(HOST)" "$(ROLE)" "$(INVENTORY)"

radio-devices: ## Name devices and judge observation freshness (HOST= ROLE= [WINDOW=])
	@./scripts/radio-devices.sh "$(HOST)" "$(ROLE)" "$(INVENTORY)"

lamp-off: ## Switch a named lamp OFF via its protocol service (HOST= ROLE= DEVICE=)
	@ACTION=off ./scripts/lamp.sh "$(HOST)" "$(ROLE)" "$(DEVICE)" "$(INVENTORY)"

lamp-on: ## Switch a named lamp ON via its protocol service (HOST= ROLE= DEVICE=)
	@ACTION=on ./scripts/lamp.sh "$(HOST)" "$(ROLE)" "$(DEVICE)" "$(INVENTORY)"

agent-plan: ## What installing the FleetForge agent would change (HOST= ROLE=)
	@ACTION=plan ./scripts/agent.sh "$(HOST)" "$(ROLE)" "$(INVENTORY)"

agent-install: ## Install and enrol the agent, preserving existing identity (HOST= ROLE=)
	@ACTION=install ./scripts/agent.sh "$(HOST)" "$(ROLE)" "$(INVENTORY)"

agent-status: ## Agent version, last-cycle result and collector settings (HOST= ROLE=)
	@ACTION=status ./scripts/agent.sh "$(HOST)" "$(ROLE)" "$(INVENTORY)"

radio-backup: ## Archive protocol state with a checksum manifest (HOST= ROLE= BACKUP_DIR= [DRY_RUN=1])
	@./scripts/radio-backup.sh "$(HOST)" "$(ROLE)" "$(BACKUP_DIR)" "$(INVENTORY)"

scenario-restore: ## Return a lamp to its documented baseline — destroys nothing (HOST= ROLE= DEVICE=)
	@ACTION=scenario-restore ./scripts/reset.sh "$(HOST)" "$(ROLE)" "$(INVENTORY)"

agent-remove: ## Remove the FleetForge agent, keeping pairings and identity (HOST= CONFIRM=HOST)
	@ACTION=agent-remove ./scripts/reset.sh "$(HOST)" "$(ROLE)" "$(INVENTORY)"

protocol-data-reset: ## DESTROYS the radio network and every pairing (HOST= ROLE= CONFIRM=HOST)
	@ACTION=protocol-data-reset ./scripts/reset.sh "$(HOST)" "$(ROLE)" "$(INVENTORY)"

host-reset: ## DESTROYS everything the lab installed on one host (HOST= CONFIRM=HOST)
	@ACTION=host-reset ./scripts/reset.sh "$(HOST)" "$(ROLE)" "$(INVENTORY)"
