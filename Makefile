# ==============================================================================
# Makefile for dfnix (Flakeless NixOS Live ISO Build System)
# ==============================================================================

.PHONY: help iso check test-qemu clean

help:
	@echo "dfnix Build System (Flakeless NixOS)"
	@echo ""
	@echo "Targets:"
	@echo "  make iso         Build the live bootable forensic ISO (./result-iso)"
	@echo "  make check       Verify Nix syntax and evaluate system closure"
	@echo "  make test-qemu   Launch the built ISO in QEMU with a test evidence drive"
	@echo "  make clean       Remove Nix build results and temporary artifacts"
	@echo ""

iso:
	@echo "==> Building dfnix live bootable ISO (flakeless)..."
	nix-build -A iso -o result-iso

check:
	@echo "==> Evaluating configuration syntax..."
	nix-instantiate --eval -E '(import ./default.nix {}).system.drvPath'

test-qemu:
	@echo "==> Preparing dummy test evidence drive..."
	@if [ ! -f test-evidence.raw ]; then \
		qemu-img create -f raw test-evidence.raw 1G; \
		mkfs.ext4 -F test-evidence.raw; \
	fi
	@echo "==> Launching dfnix ISO in QEMU..."
	qemu-system-x86_64 \
		-m 8G \
		-enable-kvm \
		-cpu host \
		-smp 4 \
		-cdrom result-iso/iso/*.iso \
		-boot d \
		-drive file=test-evidence.raw,format=raw,if=virtio

clean:
	@echo "==> Cleaning build results..."
	rm -rf result* test-evidence.raw
