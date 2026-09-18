# ==============================================================================
# Makefile for dfnix (Flakeless NixOS Live ISO Build System)
# ==============================================================================

.PHONY: help iso vm check test-qemu test-vm test-headless flash clean

DEV ?= /dev/sda

help:
	@echo "dfnix Build System (Flakeless NixOS)"
	@echo ""
	@echo "Build Targets:"
	@echo "  make iso            Build the live bootable forensic ISO (./result-iso)"
	@echo "  make vm             Build instant prototyping VM closure (./result-vm, fast: no squashfs)"
	@echo "  make check          Verify Nix syntax and evaluate system closure"
	@echo ""
	@echo "Virtualization & Testing Targets:"
	@echo "  make test-qemu      Run built ISO in QEMU (auto GUI on hpfury, SPICE/VNC on hp-nix)"
	@echo "  make test-vm        Run instant VM for rapid prototyping (auto GUI or headless)"
	@echo "  make test-headless  Force headless QEMU with SPICE (5930), VNC (5901), & SSH (2222)"
	@echo ""
	@echo "Deployment & Utilities:"
	@echo "  make flash          Flash the built ISO onto USB stick (default: DEV=/dev/sda)"
	@echo "  make clean          Remove Nix build results and temporary drive artifacts"
	@echo ""

iso:
	@echo "==> Building dfnix live bootable ISO (flakeless)..."
	nix-build -A iso -o result-iso

vm:
	@echo "==> Building dfnix rapid prototyping VM (skipping squashfs)..."
	nix-build -A vm -o result-vm

flash:
	@echo "==> Flashing dfnix ISO onto $(DEV)..."
	@./scripts/flash.sh $(DEV)

check:
	@echo "==> Evaluating configuration syntax..."
	nix-instantiate --eval -E '(import ./default.nix {}).system.drvPath'

test-qemu:
	@./scripts/run-vm.sh --iso

test-vm:
	@./scripts/run-vm.sh --vm

test-headless:
	@./scripts/run-vm.sh --headless

clean:
	@echo "==> Cleaning build results..."
	rm -rf result* test-evidence.raw test-target.raw
