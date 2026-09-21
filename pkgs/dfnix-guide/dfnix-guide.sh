#!/usr/bin/env bash
# ==============================================================================
# dfnix-guide: Interactive Quick Start Guide & Keybinding Cheat Sheet for dfnix
# Explains storage mounting, hardware triage, disk imaging, and Niri navigation.
# ==============================================================================

set -euo pipefail

# Handle non-interactive raw text dump or help
if [[ "${1:-}" == "--raw" ]]; then
    # Will be handled after render_guide definition
    RAW_MODE=1
fi

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    echo "dfnix-guide: Interactive Quick Start Guide & Keybinding Cheat Sheet"
    echo "Usage: dfnix-guide [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --raw      Output plain text without ANSI codes or pager (for piping)"
    echo "  --inner    Run pager directly inside current terminal"
    echo "  -h, --help Show this help message"
    exit 0
fi

# If not running inside an interactive terminal, spawn in a floating Kitty window
if [[ "${1:-}" != "--raw" && "${1:-}" != "--inner" ]] && [[ ! -t 0 || -z "${TERM:-}" || "${TERM:-}" == "dumb" ]]; then
    if command -v kitty >/dev/null 2>&1; then
        exec kitty \
            --class "dfnix-guide" \
            --title "dfnix - Quick Start Guide" \
            -o font_size=11.5 \
            -o window_padding_width=16 \
            -o initial_window_width=95c \
            -o initial_window_height=38c \
            "$0" --inner "$@"
    fi
fi

# ANSI Colors
BOLD=$(printf '\033[1m')
DIM=$(printf '\033[2m')
NC=$(printf '\033[0m')
CYAN=$(printf '\033[0;36m')
B_CYAN=$(printf '\033[1;36m')
BLUE=$(printf '\033[0;34m')
B_BLUE=$(printf '\033[1;34m')
GREEN=$(printf '\033[0;32m')
B_GREEN=$(printf '\033[1;32m')
YELLOW=$(printf '\033[0;33m')
B_YELLOW=$(printf '\033[1;33m')
RED=$(printf '\033[0;31m')
B_RED=$(printf '\033[1;31m')
MAGENTA=$(printf '\033[0;35m')
B_MAGENTA=$(printf '\033[1;35m')
WHITE=$(printf '\033[1;37m')

render_guide() {
    cat <<EOF
${B_CYAN}╔══════════════════════════════════════════════════════════════════════════════╗${NC}
${B_CYAN}║              dfnix — Forensic Live Environment Quick Start Guide             ║${NC}
${B_CYAN}╚══════════════════════════════════════════════════════════════════════════════╝${NC}
${DIM}Press [q] or [Ctrl+C] to exit  •  Use Arrow Keys or [PageUp]/[PageDown] to scroll${NC}
${DIM}Press [/] followed by a word to search (e.g. /mount, /image, /niri)${NC}

${B_GREEN}■ THE 3-STEP FORENSIC WORKFLOW${NC}
────────────────────────────────────────────────────────────────────────────────
In ${BOLD}dfnix${NC}, physical storage media is protected by a ${BOLD}5-layer write-blocker${NC}
(kernel parameter neutralization, swap inactivation, udev blockdev ro-enforcement,
and zero-journal replay). The standard field acquisition workflow follows 3 steps:

    ${B_CYAN}[ Step 1: Mount Target ]${NC}  ──►  ${B_BLUE}[ Step 2: System Triage ]${NC}  ──►  ${B_MAGENTA}[ Step 3: Image Disk ]${NC}
        Launch ${BOLD}dfmount${NC}                 Launch ${BOLD}dfinfo${NC}                   Launch ${BOLD}dfdisk${NC}
       (${YELLOW}Mod+M${NC} or Top Bar)             (${YELLOW}Mod+I${NC} or Top Bar)             (${YELLOW}Mod+D${NC} or Top Bar)
   Unblock destination drive       Collect hardware specs        Acquire E01 / RAW image
    under ${GREEN}/media/target${NC}             & export SHA-256 report       with hash verification

════════════════════════════════════════════════════════════════════════════════
${B_YELLOW}1. HOW TO MOUNT STORAGE DRIVES (dfmount)${NC}
════════════════════════════════════════════════════════════════════════════════
${BOLD}Shortcut:${NC} Press ${YELLOW}Mod+M${NC} or click the ${BOLD}dfmount${NC} button on the top bar.
${BOLD}Terminal:${NC} Run ${CYAN}sudo dfmount${NC}

${B_GREEN}▶ Mounting a Target / Destination Drive (To store images & reports):${NC}
  1. Connect your external USB storage or destination disk (e.g. ${BOLD}/dev/sdc1${NC}).
  2. Launch ${BOLD}dfmount${NC}.
  3. Select your destination drive from the list.
  4. Choose ${GREEN}Mount Target (Read/Write)${NC}.
  5. The drive is unblocked and mounted at:
     ${BOLD}${GREEN}/media/target/<device-name>${NC}  (e.g. ${GREEN}/media/target/sdc1${NC})
  6. All forensic tools (${BOLD}dfdisk${NC}, ${BOLD}dfinfo${NC}, X-Ways) can now write evidence files here.

${B_BLUE}▶ Mounting an Evidence Drive (Strict Read-Only Examination):${NC}
  1. Select the suspect drive or partition in ${BOLD}dfmount${NC}.
  2. Choose ${BLUE}Mount Evidence (Strict Read-Only)${NC}.
  3. The drive is mounted write-blocked with zero-journal replay under:
     ${BOLD}${BLUE}/media/evidence/<device-name>${NC}
     - ext4:  ${DIM}ro,noload (no journal replay)${NC}
     - XFS:   ${DIM}ro,norecovery (no log recovery)${NC}
     - Btrfs: ${DIM}ro,rescue=nologreplay (read-only rescue)${NC}

${DIM}CLI Shortcuts:
  sudo dfmount target /dev/sdc1      # Mount target drive writeable
  sudo dfmount evidence /dev/sdb1    # Mount evidence drive write-blocked
  sudo dfmount unblock /dev/sdc      # Unblock physical drive without mounting
  sudo dfmount unmount /dev/sdc1     # Safely unmount filesystem${NC}

════════════════════════════════════════════════════════════════════════════════
${B_YELLOW}2. HOW TO GET HARDWARE INFO & TRIAGE (dfinfo)${NC}
════════════════════════════════════════════════════════════════════════════════
${BOLD}Shortcut:${NC} Press ${YELLOW}Mod+I${NC} or click the ${BOLD}dfinfo${NC} button on the top bar.
${BOLD}Terminal:${NC} Run ${CYAN}sudo dfinfo${NC}

${B_GREEN}▶ Interactive Hardware Triage:${NC}
  ${BOLD}dfinfo${NC} displays a comprehensive hardware overview in your terminal:
  • ${BOLD}Fastfetch Overview:${NC} Host model, CPU cores, RAM size, GPU, OS, uptime.
  • ${BOLD}DMI / BIOS Identifiers:${NC} System Manufacturer, Serial Number, UUID,
    Motherboard revision, BIOS vendor, version, and release date.
  • ${BOLD}Storage Devices:${NC} Block device inventory (${CYAN}lsblk${NC}) showing transport,
    model, serial, and write-blocking status (${GREEN}RO=1${NC}).
  • ${BOLD}Network Links:${NC} All physical & wireless interfaces with permanent MAC addresses.
  • ${BOLD}Peripherals:${NC} USB hardware devices (${CYAN}lsusb${NC}) and PCI controllers.

${B_GREEN}▶ Exporting Verifiable Forensic Triage Reports (.txt):${NC}
  • Inside ${BOLD}dfinfo${NC}, press ${YELLOW}[R]${NC} to generate a report, or pass ${CYAN}--report${NC}:
    ${CYAN}sudo dfinfo --report${NC}
  • The report is automatically saved to ${GREEN}/media/target${NC} (or ~/Desktop).
  • A cryptographic ${BOLD}SHA-256 integrity hash${NC} is calculated and appended to the report.

${DIM}CLI Shortcuts:
  sudo dfinfo --report               # Export report to /media/target with SHA-256
  sudo dfinfo --export /path/to/dir  # Export report to custom folder
  sudo dfinfo --stdout               # Stream plain-text report directly to pipe${NC}

════════════════════════════════════════════════════════════════════════════════
${B_YELLOW}3. HOW TO IMAGE DISKS (dfdisk)${NC}
════════════════════════════════════════════════════════════════════════════════
${BOLD}Shortcut:${NC} Press ${YELLOW}Mod+D${NC} or click the ${BOLD}dfdisk${NC} button on the top bar.
${BOLD}Terminal:${NC} Run ${CYAN}sudo dfdisk${NC}

${B_GREEN}▶ Disk Acquisition Steps:${NC}
  1. Launch ${BOLD}dfdisk${NC}.
  2. ${BOLD}Select Source:${NC} Choose the suspect disk (e.g. ${CYAN}/dev/sdb${NC} or NVMe).
  3. ${BOLD}Choose Format:${NC}
     • ${B_CYAN}E01 (Expert Witness Format / EnCase):${NC} Industry standard. Compresses
       data chunks, stores case metadata (examiner, case #), and embeds MD5/SHA-256.
     • ${B_BLUE}RAW / DD:${NC} Exact sector-by-sector raw disk image.
     • ${B_RED}ddrescue (Damaged Media):${NC} Multi-phase rescue for drives with bad
       sectors, using a resume mapfile to avoid stressing failing hardware.
  4. ${BOLD}Set Destination Directory:${NC} Browse to your unblocked target storage
     (e.g. ${GREEN}/media/target/sdc1/case_2026/${NC}).
  5. ${BOLD}Start Acquisition:${NC} Monitor real-time throughput, ETA, and bad block count.
  6. ${BOLD}Verification:${NC} Hashes are verified automatically after completion.

════════════════════════════════════════════════════════════════════════════════
${B_YELLOW}4. NIRI DESKTOP & WORKSPACE NAVIGATION${NC}
════════════════════════════════════════════════════════════════════════════════
${BOLD}dfnix${NC} uses ${BOLD}Niri${NC}, a modern, fluid scrollable-tiling Wayland compositor.
Windows are arranged in vertical columns that scroll horizontally.

${B_CYAN}┌──────────────────────────────────────────────────────────────────────────────┐${NC}
${B_CYAN}│ KEYBINDING             ACTION                                                │${NC}
${B_CYAN}├──────────────────────────────────────────────────────────────────────────────┤${NC}
│ ${YELLOW}F1${NC} or ${YELLOW}Mod + F1${NC}         ${WHITE}Toggle this Quick Start Guide (Floating Info Window)${NC}  │
│ ${YELLOW}Mod + Space${NC}             ${WHITE}Toggle Noctalia Application Launcher${NC}                  │
│ ${YELLOW}Mod + S${NC}                 ${WHITE}Toggle Noctalia Control Center (Audio, Wi-Fi, Power)${NC}  │
│ ${YELLOW}Mod + Return${NC} / ${YELLOW}Mod + T${NC}  ${WHITE}Open Kitty Terminal${NC}                                   │
│ ${YELLOW}Mod + E${NC}                 ${WHITE}Open Dolphin File Manager${NC}                             │
│ ${YELLOW}Mod + B${NC}                 ${WHITE}Open Firefox Web Browser${NC}                              │
│ ${YELLOW}Mod + D${NC}                 ${WHITE}Launch dfdisk Forensic Imager (sudo)${NC}                  │
│ ${YELLOW}Mod + M${NC}                 ${WHITE}Launch dfmount Storage Manager (sudo)${NC}                 │
│ ${YELLOW}Mod + N${NC}                 ${WHITE}Launch dfnet Network Operations (sudo)${NC}                │
│ ${YELLOW}Mod + I${NC}                 ${WHITE}Launch dfinfo System Triage (sudo)${NC}                   │
│ ${YELLOW}Mod + Shift + E${NC}         ${WHITE}Session Menu / Logout / Power Off${NC}                     │
├──────────────────────────────────────────────────────────────────────────────┤
│ ${B_GREEN}WORKSPACES (VERTICAL NAVIGATION)${NC}                                             │
│ ${YELLOW}Mod + Down${NC} / ${YELLOW}Mod + J${NC}    ${WHITE}Navigate to workspace below${NC}                           │
│ ${YELLOW}Mod + Up${NC}   / ${YELLOW}Mod + K${NC}    ${WHITE}Navigate to workspace above${NC}                           │
│ ${YELLOW}Mod + Shift + Down/J${NC}   ${WHITE}Move active column to workspace below${NC}                 │
│ ${YELLOW}Mod + Shift + Up/K${NC}     ${WHITE}Move active column to workspace above${NC}                 │
│ ${YELLOW}Mod + 1 .. 5${NC}           ${WHITE}Switch directly to workspace 1 through 5${NC}              │
│ ${YELLOW}Mod + Shift + 1 .. 5${NC}   ${WHITE}Move active column to workspace 1 through 5${NC}           │
├──────────────────────────────────────────────────────────────────────────────┤
│ ${B_BLUE}COLUMNS & HORIZONTAL SCROLLING${NC}                                              │
│ ${YELLOW}Mod + Left${NC} / ${YELLOW}Mod + H${NC}    ${WHITE}Focus column to the left${NC}                              │
│ ${YELLOW}Mod + Right${NC} / ${YELLOW}Mod + L${NC}   ${WHITE}Focus column to the right${NC}                             │
│ ${YELLOW}Mod + Shift + Left/H${NC}   ${WHITE}Move active column to the left${NC}                        │
│ ${YELLOW}Mod + Shift + Right/L${NC}  ${WHITE}Move active column to the right${NC}                       │
│ ${YELLOW}Mod + C${NC}                 ${WHITE}Center active column on screen${NC}                        │
│ ${YELLOW}Mod + R${NC}                 ${WHITE}Switch column preset width (33% ──► 50% ──► 66% ──► 100%)${NC}│
│ ${YELLOW}Mod + F${NC}                 ${WHITE}Maximize column width to fill screen${NC}                  │
│ ${YELLOW}Mod + Shift + F${NC}         ${WHITE}Toggle fullscreen window${NC}                              │
├──────────────────────────────────────────────────────────────────────────────┤
│ ${B_MAGENTA}WINDOWS & FLOATING${NC}                                                         │
│ ${YELLOW}Mod + Page_Down${NC}         ${WHITE}Focus window below (in stacked column)${NC}               │
│ ${YELLOW}Mod + Page_Up${NC}           ${WHITE}Focus window above (in stacked column)${NC}               │
│ ${YELLOW}Mod + Shift + PgDown${NC}   ${WHITE}Move window down within column${NC}                        │
│ ${YELLOW}Mod + Shift + PgUp${NC}     ${WHITE}Move window up within column${NC}                          │
│ ${YELLOW}Mod + W${NC}                 ${WHITE}Toggle floating mode for active window${NC}                │
│ ${YELLOW}Mod + Q${NC}                 ${WHITE}Close active window${NC}                                   │
${B_CYAN}└──────────────────────────────────────────────────────────────────────────────┘${NC}

════════════════════════════════════════════════════════════════════════════════
${B_YELLOW}5. ADVANCED TOOLS & CAPABILITIES${NC}
════════════════════════════════════════════════════════════════════════════════
• ${BOLD}X-Ways Forensics (Wine):${NC}
  Run portable X-Ways with hardware dongle passthrough and raw physical disk
  access. Launch via Noctalia launcher or CLI:
  ${CYAN}xways${NC}                         # Native floating multi-window mode
  ${CYAN}xways --desktop${NC}               # Single contained window (virtual desktop)

• ${BOLD}Network Triage & Acquisition (dfnet):${NC}
  Launch with ${YELLOW}Mod+N${NC} or ${CYAN}sudo dfnet${NC}. Provides MAC address spoofing,
  NetworkManager TUI (${CYAN}nmtui${NC}), network share mounting (SMB/NFS/SSHFS), and
  receiving incoming raw disk dumps over netcat/socat.

• ${BOLD}Air-Gapped Offline Documentation:${NC}
  Search pre-indexed offline manpages anytime:
  ${CYAN}man -k forensic${NC}                 # Search offline man pages
  ${CYAN}man ewfacquire${NC}                  # View specific manual

────────────────────────────────────────────────────────────────────────────────
${DIM}Tip: You can redisplay this guide anytime by hitting [F1] or clicking [Info] on the top bar.${NC}
EOF
}

# If stdout is a pipe or redirected, or if --raw is requested, output clean text
if [[ "${1:-}" == "--raw" ]] || [[ ! -t 1 ]]; then
    render_guide | sed -r 's/\x1B\[[0-9;]*[a-zA-Z]//g'
    exit 0
fi

# Run in pager
render_guide | less -R -P " dfnix Quick Start Guide  |  Arrows/PageUp/PageDown: Scroll  |  /: Search  |  q: Quit "
