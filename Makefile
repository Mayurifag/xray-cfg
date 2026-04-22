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
else
  cmd_setup        := bash setup_linux.sh
  cmd_teardown     := bash teardown.sh
  cmd_test         := bash test.sh
  cmd_cycle        := bash test.sh
  cmd_status       := sudo systemctl status xray --no-pager
  cmd_logs         := sudo journalctl -u xray -f
  cmd_flush_dns    := sudo resolvectl flush-caches
  cmd_geodata      := bash update_geodata.sh
  cmd_add_domain   := bash add_domain.sh $(domain) $(proxy)
  cmd_rm_domain    := bash remove_domain.sh $(domain)
endif

# ── targets ───────────────────────────────────────────────────────────────────
ci: cycle

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
