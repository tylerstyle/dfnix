#!/usr/bin/env bash
# ==============================================================================
# dfnix Virtualization & Fast Prototyping Runner
#
# Supports:
#   1. Local GUI Workstation with VirtIO-GPU & Tablet
#   2. Headless Server with SPICE (5930), VNC (5901), & SSH (2222)
#   3. Instant NixOS VM (result-vm/bin/run-*-vm) for fast iteration (no ISO build)
#   4. Full Live ISO Testing (result-iso/iso/*.iso) with simulated evidence drives
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"

MODE="auto" # auto, iso, vm
DISPLAY_MODE="auto" # auto, gui, headless, vnc, spice
RAM="8G"
CPUS="4"
VNC_PORT="1" # 5901
SPICE_PORT="5930"
SSH_PORT="2222"

print_help() {
    cat << 'EOF'
dfnix Virtualization Runner

Usage: ./scripts/run-vm.sh [OPTIONS]

Modes:
  --iso              Boot the built ISO image (result-iso/iso/*.iso)
  --vm               Boot the instant NixOS VM closure (result-vm/bin/run-*-vm)
                     (Fastest prototyping: skips squashfs compression and ISO packaging)

Display Options:
  --gui              Force native graphical window (for local desktop)
  --headless         Force headless mode with SPICE, VNC, and SSH forward (for remote server)
  --vnc              Headless with VNC only (port 5901)
  --spice            Headless with SPICE only (port 5930)

Hardware Options:
  --ram <size>       RAM size for VM (default: 8G, minimum 4G for copytoram)
  --cpus <num>       Number of CPU cores (default: 4)
  --ssh-port <port>  Host port to forward to guest SSH port 22 (default: 2222)
  --spice-port <num> SPICE listening port (default: 5930)
  --vnc-port <num>   VNC display offset (default: 1 -> port 5901)
  -h, --help         Show this help message

Examples:
  # Fast prototyping on remote server (headless):
  ./scripts/run-vm.sh --headless

  # Local interactive testing on desktop workstation:
  ./scripts/run-vm.sh --gui

  # Rapid iteration with instant NixOS VM:
  make vm
  ./scripts/run-vm.sh --vm
EOF
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --iso)
            MODE="iso"
            shift
            ;;
        --vm)
            MODE="vm"
            shift
            ;;
        --gui)
            DISPLAY_MODE="gui"
            shift
            ;;
        --headless)
            DISPLAY_MODE="headless"
            shift
            ;;
        --vnc)
            DISPLAY_MODE="vnc"
            shift
            ;;
        --spice)
            DISPLAY_MODE="spice"
            shift
            ;;
        --ram)
            RAM="$2"
            shift 2
            ;;
        --cpus)
            CPUS="$2"
            shift 2
            ;;
        --ssh-port)
            SSH_PORT="$2"
            shift 2
            ;;
        --spice-port)
            SPICE_PORT="$2"
            shift 2
            ;;
        --vnc-port)
            VNC_PORT="$2"
            shift 2
            ;;
        -h|--help)
            print_help
            exit 0
            ;;
        *)
            echo "[-] Unknown option: $1"
            print_help
            exit 1
            ;;
    esac
done

echo "========================================================================"
echo "                   dfnix Virtualization Environment                     "
echo "========================================================================"

# Detect KVM acceleration
KVM_OPTS=()
if [ -c /dev/kvm ] && [ -w /dev/kvm ]; then
    echo "[+] KVM acceleration available (/dev/kvm)"
    KVM_OPTS=(-enable-kvm -cpu host)
else
    echo "[!] WARNING: /dev/kvm not writeable or unavailable. Running in emulation mode."
    KVM_OPTS=(-cpu max)
fi

EVIDENCE_IMG="${SCRIPT_DIR}/test-evidence.raw"
TARGET_IMG="${SCRIPT_DIR}/test-target.raw"

# Prepare simulated forensic evidence drive and destination/target drive
if [ ! -f "$EVIDENCE_IMG" ]; then
    echo "[*] Creating 1GB dummy evidence drive (test-evidence.raw)..."
    qemu-img create -f raw "$EVIDENCE_IMG" 1G >/dev/null
    mkfs.ext4 -F -L "EVIDENCE_SUSPECT" "$EVIDENCE_IMG" >/dev/null 2>&1 || true
fi

if [ ! -f "$TARGET_IMG" ]; then
    echo "[*] Creating 2GB dummy target drive for acquisition dumps (test-target.raw)..."
    qemu-img create -f raw "$TARGET_IMG" 2G >/dev/null
    mkfs.ext4 -F -L "TARGET_STORE" "$TARGET_IMG" >/dev/null 2>&1 || true
fi

# Auto-detect Mode if not set
if [ "$MODE" = "auto" ]; then
    if [ -d "result-vm" ] && [ -e "result-vm" ]; then
        MODE="vm"
    elif compgen -G "result-iso/iso/*.iso" >/dev/null 2>&1 || compgen -G "result/iso/*.iso" >/dev/null 2>&1; then
        MODE="iso"
    else
        echo "[-] Error: Neither working result-vm nor result-iso found on this host."
        if [ -L "result-vm" ] && [ ! -e "result-vm" ]; then
            echo "    * Note: result-vm exists as a broken symlink synced from another host."
        fi
        echo "    Build the prototyping VM with: make vm"
        echo "    Or build the full ISO with   : make iso"
        exit 1
    fi
fi

# Auto-detect Display Mode if not explicitly specified
HOSTNAME_CURRENT="$(hostname 2>/dev/null || echo "unknown")"
if [ "$DISPLAY_MODE" = "auto" ]; then
    if [ -n "${WAYLAND_DISPLAY:-}" ] || [ -n "${DISPLAY:-}" ]; then
        DISPLAY_MODE="gui"
    else
        DISPLAY_MODE="headless"
    fi
fi

echo "[+] Target Mode  : $MODE"
echo "[+] Display Mode : $DISPLAY_MODE (Host: $HOSTNAME_CURRENT)"
echo "[+] Resources    : $RAM RAM, $CPUS SMP Cores"
echo "------------------------------------------------------------------------"

# ------------------------------------------------------------------------------
# 1. Fast NixOS VM Runner (system.build.vm)
# ------------------------------------------------------------------------------
if [ "$MODE" = "vm" ]; then
    if [ ! -d "result-vm/bin" ] || [ ! -e "result-vm" ]; then
        echo "[-] Error: VM script not found in result-vm/bin/"
        if [ -L "result-vm" ] && [ ! -e "result-vm" ]; then
            echo "    * Note: result-vm is a dangling symlink from another build host."
        fi
        echo "    Please build the VM on this host first:"
        echo "    Run: make vm (or nix-build -A vm -o result-vm)"
        exit 1
    fi

    VM_SCRIPT=$(find result-vm/bin/ -name "run-*-vm" 2>/dev/null | head -n 1 || true)
    if [ -z "$VM_SCRIPT" ] || [ ! -x "$VM_SCRIPT" ]; then
        echo "[-] Error: VM script not found in result-vm/bin/"
        echo "    Build it with: make vm"
        exit 1
    fi

    EXTRA_QEMU_OPTS="${KVM_OPTS[*]}"
    EXTRA_QEMU_OPTS="${EXTRA_QEMU_OPTS} -drive file=${EVIDENCE_IMG},format=raw,if=virtio,id=evidence"
    EXTRA_QEMU_OPTS="${EXTRA_QEMU_OPTS} -drive file=${TARGET_IMG},format=raw,if=virtio,id=target"
    export QEMU_NET_OPTS="hostfwd=tcp::${SSH_PORT}-:22"

    # Detect hardware-accelerated 3D graphics (VirGL) for Wayland compositors (Niri)
    GUI_GPU_OPTS=()
    if [ "$DISPLAY_MODE" = "gui" ]; then
        if qemu-system-x86_64 -display gtk,gl=on -device virtio-vga-gl -help >/dev/null 2>&1; then
            GUI_GPU_OPTS=(-device virtio-vga-gl -display "gtk,gl=on")
        elif qemu-system-x86_64 -display sdl,gl=on -device virtio-vga-gl -help >/dev/null 2>&1; then
            GUI_GPU_OPTS=(-device virtio-vga-gl -display "sdl,gl=on")
        else
            GUI_GPU_OPTS=(-vga virtio)
        fi
        EXTRA_QEMU_OPTS="${EXTRA_QEMU_OPTS} ${GUI_GPU_OPTS[*]}"
    else
        EXTRA_QEMU_OPTS="${EXTRA_QEMU_OPTS} -vga virtio -device usb-tablet"
        EXTRA_QEMU_OPTS="${EXTRA_QEMU_OPTS} -spice port=${SPICE_PORT},addr=127.0.0.1,disable-ticketing=on"
        EXTRA_QEMU_OPTS="${EXTRA_QEMU_OPTS} -display vnc=127.0.0.1:${VNC_PORT}"

        echo ">>> Headless access endpoints (bound to localhost for security):"
        echo "    * Local SPICE: remote-viewer spice://127.0.0.1:${SPICE_PORT}"
        echo "    * Local VNC  : vncviewer 127.0.0.1:$((5900 + VNC_PORT))"
        echo "    * Local SSH  : ssh -p ${SSH_PORT} nixos@localhost"
        echo "    * Remote SSH Tunnel (from client): ssh -L $((5900 + VNC_PORT)):127.0.0.1:$((5900 + VNC_PORT)) -L ${SPICE_PORT}:127.0.0.1:${SPICE_PORT} ${HOSTNAME_CURRENT}"
        echo "------------------------------------------------------------------------"
    fi

    echo "[*] Launching instant NixOS VM..."
    export QEMU_OPTS="${EXTRA_QEMU_OPTS}"
    exec "$VM_SCRIPT"
fi

# ------------------------------------------------------------------------------
# 2. Live Bootable ISO Runner (result-iso/iso/*.iso)
# ------------------------------------------------------------------------------
ISO_PATH=$(find result-iso/iso result/iso -name "*.iso" 2>/dev/null | head -n 1 || true)
if [ -z "$ISO_PATH" ] || [ ! -f "$ISO_PATH" ]; then
    echo "[-] Error: No ISO file found in result-iso/iso or result/iso"
    echo "    Build it first with: make iso"
    exit 1
fi

echo "[+] ISO Image    : $ISO_PATH ($(du -h "$ISO_PATH" | cut -f1))"

QEMU_CMD=(
    qemu-system-x86_64
    -m "$RAM"
    -smp "$CPUS"
    "${KVM_OPTS[@]}"
    -boot d
    -cdrom "$ISO_PATH"
    -drive "file=${EVIDENCE_IMG},format=raw,if=virtio,id=evidence"
    -drive "file=${TARGET_IMG},format=raw,if=virtio,id=target"
    -nic "user,model=virtio-net-pci,hostfwd=tcp::${SSH_PORT}-:22"
)

if [ "$DISPLAY_MODE" = "gui" ]; then
    if qemu-system-x86_64 -display gtk,gl=on -device virtio-vga-gl -help >/dev/null 2>&1; then
        ISO_GPU_OPTS=(-device virtio-vga-gl -display "gtk,gl=on")
    elif qemu-system-x86_64 -display sdl,gl=on -device virtio-vga-gl -help >/dev/null 2>&1; then
        ISO_GPU_OPTS=(-device virtio-vga-gl -display "sdl,gl=on")
    else
        ISO_GPU_OPTS=(-vga virtio)
    fi
    QEMU_CMD+=(
        "${ISO_GPU_OPTS[@]}"
        -usb
        -device usb-tablet
    )
else
    VNC_DISPLAY_NUM=$((5900 + VNC_PORT))
    QEMU_CMD+=(
        -vga virtio
        -usb
        -device usb-tablet
        -spice "port=${SPICE_PORT},addr=127.0.0.1,disable-ticketing=on"
        -display "vnc=127.0.0.1:${VNC_PORT}"
    )

    echo ">>> Headless access endpoints (bound to localhost for security):"
    echo "    * Local SPICE: remote-viewer spice://127.0.0.1:${SPICE_PORT}"
    echo "    * Local VNC  : vncviewer 127.0.0.1:${VNC_DISPLAY_NUM}"
    echo "    * Local SSH  : ssh -p ${SSH_PORT} nixos@localhost"
    echo "    * Remote SSH Tunnel (from local client): ssh -L ${VNC_DISPLAY_NUM}:127.0.0.1:${VNC_DISPLAY_NUM} -L ${SPICE_PORT}:127.0.0.1:${SPICE_PORT} ${HOSTNAME_CURRENT}"
    echo "------------------------------------------------------------------------"
fi

echo "[*] Launching QEMU..."
exec "${QEMU_CMD[@]}"
