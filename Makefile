# ==============================================================================
# Makefile for dfnix (NixOS Live ISO & Appliance Build System)
# ==============================================================================

.PHONY: help iso iso-nvidia vm vmware virtualbox check test-cftt test-tools test-xways test-nvidia test-qemu test-qemu-nvidia test-vm test-headless flash flash-nvidia clean

help:
	@echo "dfnix Build System"
	@echo ""
	@echo "Build Targets:"
	@echo "  make iso            Build the standard live ISO: dfnix-forensics.iso (./result-iso)"
	@echo "  make iso-nvidia     Build the NVIDIA live ISO: dfnix-forensics-nvidia.iso (./result-iso-nvidia)"
	@echo "                      NVIDIA driver + CUDA runtime, for RTX 20 / GTX 16 series and newer."
	@echo "                      Contains unfree NVIDIA software; every other machine takes 'make iso'."
	@echo "  make vm             Build instant prototyping VM closure (./result-vm, fast: no squashfs)"
	@echo "  make vmware         Build VMware appliance (.vmdk, ./result-vmware)"
	@echo "  make virtualbox     Build VirtualBox appliance (.ova, ./result-vbox)"
	@echo "  make check          Verify Nix syntax and evaluate system closure"
	@echo ""
	@echo "Virtualization & Testing Targets:"
	@echo "  make test-cftt      Write-blocking regression test (KVM)"
	@echo "  make test-tools     Run forensic tools startup smoke check"
	@echo "  make test-xways     Run X-Ways launcher VM test (KVM)"
	@echo "  make test-nvidia    Check the NVIDIA image's driver and CUDA libraries (no GPU needed or tested)"
	@echo "  make test-qemu      Run built ISO in QEMU (auto GUI on desktop, SPICE/VNC on headless server)"
	@echo "  make test-qemu-nvidia  Run the built NVIDIA ISO in QEMU (no NVIDIA card there: fallback path)"
	@echo "  make test-vm        Run instant VM for rapid prototyping (auto GUI or headless)"
	@echo "  make test-headless  Force headless QEMU with SPICE (5930), VNC (5901), & SSH (2222)"
	@echo ""
	@echo "  Builds use the inputs pinned in flake.lock. LOCAL_TOOLS=1 builds against the committed"
	@echo "  HEAD of ../dfcore, ../dfdisk, ../dfmount, ../dfnet, ../dflive and ../dfcollect"
	@echo "  instead (tool development)."
	@echo ""
	@echo "Deployment & Utilities:"
	@echo "  make flash DEV=/dev/sdX         Flash the standard ISO onto USB stick (requires DEV)"
	@echo "  make flash-nvidia DEV=/dev/sdX  Flash the NVIDIA ISO onto USB stick (requires DEV)"
	@echo "                      Any other image: make flash DEV=/dev/sdX ISO=/path/to/image.iso"
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

iso-nvidia:
	@echo "==> Building dfnix live bootable ISO with NVIDIA driver and CUDA (unfree software)..."
	nix build .#iso-nvidia $(TOOL_OVERRIDES) -o result-iso-nvidia

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
	@./scripts/flash.sh "$(DEV)" $(if $(ISO),--iso "$(ISO)")

flash-nvidia:
ifndef DEV
	@echo "[-] Error: Target USB device not specified."
	@echo "    Usage: make flash-nvidia DEV=/dev/sdX"
	@exit 1
endif
	@echo "==> Flashing dfnix NVIDIA ISO onto $(DEV)..."
	@./scripts/flash.sh "$(DEV)" --iso result-iso-nvidia/iso/dfnix-forensics-nvidia.iso

check:
	@echo "==> Running flake evaluation checks..."
	nix flake check --no-build $(TOOL_OVERRIDES)
	@echo "==> Checking shell scripts..."
	nix shell --inputs-from . nixpkgs#shellcheck -c shellcheck scripts/*.sh pkgs/*/*.sh tests/cftt/fixtures.sh
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

test-tools:
	@echo "==> Running forensic tools startup smoke check..."
	nix build -L .#checks.x86_64-linux.tool-smoke $(TOOL_OVERRIDES) -o result-tool-smoke

test-xways:
	@echo "==> Running X-Ways launcher VM test..."
	nix build -L .#checks.x86_64-linux.xways $(TOOL_OVERRIDES) -o result-xways

test-nvidia:
	@echo "==> Checking the NVIDIA image's driver and CUDA libraries..."
	nix build -L .#nvidia-runtime-check $(TOOL_OVERRIDES) -o result-nvidia-check

test-qemu:
	@./scripts/run-vm.sh --iso

test-qemu-nvidia:
	@./scripts/run-vm.sh --iso-nvidia

test-vm:
	@./scripts/run-vm.sh --vm

test-headless:
	@./scripts/run-vm.sh --headless

clean:
	@echo "==> Cleaning build results..."
	rm -rf result* test-evidence.raw test-target.raw
