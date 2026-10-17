# ==============================================================================
# Makefile for dfnix (NixOS Live ISO & Appliance Build System)
# ==============================================================================

.PHONY: help iso vm vmware virtualbox check test-cftt test-qemu test-vm test-headless flash clean

help:
	@echo "dfnix Build System"
	@echo ""
	@echo "Build Targets:"
	@echo "  make iso            Build the live bootable forensic ISO (./result-iso)"
	@echo "  make vm             Build instant prototyping VM closure (./result-vm, fast: no squashfs)"
	@echo "  make vmware         Build VMware appliance (.vmdk, ./result-vmware)"
	@echo "  make virtualbox     Build VirtualBox appliance (.ova, ./result-vbox)"
	@echo "  make check          Verify Nix syntax and evaluate system closure"
	@echo ""
	@echo "Virtualization & Testing Targets:"
	@echo "  make test-qemu      Run built ISO in QEMU (auto GUI on desktop, SPICE/VNC on headless server)"
	@echo "  make test-vm        Run instant VM for rapid prototyping (auto GUI or headless)"
	@echo "  make test-headless  Force headless QEMU with SPICE (5930), VNC (5901), & SSH (2222)"
	@echo "  make test-cftt      Write-blocking regression test (KVM)"
	@echo ""
	@echo "  Builds use the inputs pinned in flake.lock. LOCAL_TOOLS=1 builds against the committed"
	@echo "  HEAD of ../dfcore, ../dfdisk, ../dfmount, ../dfnet, ../dflive and ../dfcollect"
	@echo "  instead (tool development)."
	@echo ""
	@echo "Deployment & Utilities:"
	@echo "  make flash DEV=/dev/sdX  Flash the built ISO onto USB stick (requires DEV)"
	@echo "  make clean          Remove Nix build results and temporary drive artifacts"
	@echo ""

# Builds use flake.lock, so `make iso` is reproducible from the commit alone.
# LOCAL_TOOLS=1 overrides dfcore and the tools with the committed HEAD of the
# sibling repositories, for testing tool changes before they are released.
LOCAL_TOOLS ?= 0

ifeq ($(LOCAL_TOOLS),1)
TOOL_OVERRIDES = $(foreach t,dfcore dfdisk dfmount dfnet dflive dfcollect,--override-input $(t) git+file://$(abspath ../$(t)))
endif

iso:
	@echo "==> Building dfnix live bootable ISO..."
	nix build .#iso $(TOOL_OVERRIDES) -o result-iso

vm:
	@echo "==> Building dfnix rapid prototyping VM (skipping squashfs)..."
	nix build .#vm $(TOOL_OVERRIDES) -o result-vm

vmware:
	@echo "==> Building dfnix VMware appliance (.vmdk)..."
	nix build .#vmware $(TOOL_OVERRIDES) -o result-vmware

virtualbox:
	@echo "==> Building dfnix VirtualBox appliance (.ova)..."
	nix build .#virtualbox $(TOOL_OVERRIDES) -o result-vbox

flash:
ifndef DEV
	@echo "[-] Error: Target USB device not specified."
	@echo "    Usage: make flash DEV=/dev/sdX"
	@echo ""
	@echo "[*] Available removable/USB block devices:"
	@lsblk -d -o NAME,SIZE,TYPE,VENDOR,MODEL,TRAN,RM 2>/dev/null || true
	@exit 1
endif
	@echo "==> Flashing dfnix ISO onto $(DEV)..."
	@./scripts/flash.sh $(DEV)

check:
	@echo "==> Running flake evaluation checks..."
	nix flake check --no-build $(TOOL_OVERRIDES)
	@echo "==> Checking shell scripts..."
	nix shell nixpkgs#shellcheck -c shellcheck scripts/*.sh pkgs/*/*.sh tests/cftt/fixtures.sh
	@echo "==> Evaluating flakeless entry point (flake-compat)..."
	@if grep -q '"dfcore"' flake.lock; then \
		nix-instantiate --eval -E '(import ./default.nix {}).system.drvPath'; \
	else \
		echo "    skipped: dfcore is not in flake.lock yet (unpushed); flake-compat can only"; \
		echo "    evaluate locked inputs. Run 'nix flake lock' after pushing dfcore and the tools."; \
	fi

test-cftt:
	@echo "==> Running CFTT write-blocking regression test..."
	nix build -L .#checks.x86_64-linux.cftt $(TOOL_OVERRIDES) -o result-cftt

test-qemu:
	@./scripts/run-vm.sh --iso

test-vm:
	@./scripts/run-vm.sh --vm

test-headless:
	@./scripts/run-vm.sh --headless

clean:
	@echo "==> Cleaning build results..."
	rm -rf result* test-evidence.raw test-target.raw
