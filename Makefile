.PHONY: ci setup teardown test restart status logs add-domain remove-domain flush-dns update-geodata

ci:
	@if [ "$$(uname -s)" = "Linux" ]; then bash test.sh; \
	elif [ "$$OS" = "Windows_NT" ]; then powershell.exe -ExecutionPolicy Bypass -File windows/cycle.ps1; \
	else echo "[ci] Unsupported OS."; fi

setup:
	bash setup_linux.sh

teardown:
	bash teardown.sh

test:
	bash test.sh

restart: teardown setup

status:
	sudo systemctl status xray --no-pager

logs:
	sudo journalctl -u xray -f

add-domain:
	@if [ "$$(uname -s)" = "Linux" ]; then bash add_domain.sh $(domain) $(proxy); \
	elif [ "$$OS" = "Windows_NT" ]; then powershell.exe -ExecutionPolicy Bypass -File windows/add_domain.ps1 $(domain) $(proxy); \
	else echo "[add-domain] Unsupported OS."; fi

remove-domain:
	@if [ "$$(uname -s)" = "Linux" ]; then bash remove_domain.sh $(domain); \
	elif [ "$$OS" = "Windows_NT" ]; then powershell.exe -ExecutionPolicy Bypass -File windows/remove_domain.ps1 $(domain); \
	else echo "[remove-domain] Unsupported OS."; fi

flush-dns:
	sudo resolvectl flush-caches

update-geodata:
	bash update_geodata.sh
