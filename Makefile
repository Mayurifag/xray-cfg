.PHONY: ci setup teardown restart test cycle status logs flush-dns update-geodata add-domain remove-domain

# ── platform detection ────────────────────────────────────────────────────────
ifeq ($(OS),Windows_NT)
  PS := powershell.exe -ExecutionPolicy Bypass -File

  cmd_setup        := $(PS) windows/setup.ps1
  cmd_teardown     := $(PS) windows/teardown.ps1
  cmd_test         := $(PS) windows/test.ps1 -Mode all
  cmd_cycle        := $(PS) windows/cycle.ps1
  cmd_status       := $(PS) windows/status.ps1
  cmd_logs         := $(PS) windows/logs.ps1
  cmd_flush_dns    := $(PS) windows/flush_dns.ps1
  cmd_geodata      := $(PS) windows/update_geodata.ps1
  cmd_add_domain   := $(PS) windows/add_domain.ps1 $(domain) $(proxy)
  cmd_rm_domain    := $(PS) windows/remove_domain.ps1 $(domain)
  cmd_ci           := $(PS) windows/ci.ps1
else ifeq ($(shell uname),Darwin)
  cmd_setup        := bash macos/setup.sh
  cmd_teardown     := bash macos/teardown.sh
  cmd_test         := bash macos/test.sh
  cmd_cycle        := bash macos/cycle.sh
  cmd_status       := bash macos/status.sh
  cmd_logs         := bash macos/logs.sh
  cmd_flush_dns    := bash macos/flush_dns.sh
  cmd_geodata      := bash macos/update_geodata.sh
  cmd_add_domain   := bash macos/add_domain.sh $(domain) $(proxy)
  cmd_rm_domain    := bash macos/remove_domain.sh $(domain)
  cmd_ci           := bash macos/ci.sh
else
  cmd_setup        := bash linux/setup.sh
  cmd_teardown     := bash linux/teardown.sh
  cmd_test         := bash linux/test.sh
  cmd_cycle        := bash linux/cycle.sh
  cmd_status       := sudo systemctl status xray --no-pager
  cmd_logs         := sudo journalctl -u xray -f
  cmd_flush_dns    := sudo resolvectl flush-caches
  cmd_geodata      := bash linux/update_geodata.sh
  cmd_add_domain   := bash linux/add_domain.sh $(domain) $(proxy)
  cmd_rm_domain    := bash linux/remove_domain.sh $(domain)
endif

# ── targets ───────────────────────────────────────────────────────────────────
ifdef cmd_ci
ci:
	$(cmd_ci)
else
ci: cycle
endif

setup:
	$(cmd_setup)

teardown:
	$(cmd_teardown)

restart: teardown setup

test:
	$(cmd_test)

cycle:
	$(cmd_cycle)

status:
	$(cmd_status)

logs:
	$(cmd_logs)

flush-dns:
	$(cmd_flush_dns)

update-geodata:
	$(cmd_geodata)

add-domain:
	$(cmd_add_domain)

remove-domain:
	$(cmd_rm_domain)
