#!/usr/bin/env bash
# ==============================================================================
# dfinfo: Forensic System Triage & Fastfetch Reporter for dfnix
# Displays visual system hardware summary and exports concise, verifiable
# forensic triage reports (.txt) with cryptographic checksums.
# ==============================================================================

set -euo pipefail

# ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Helper: read DMI safely (falls back to /sys/class/dmi/id)
get_dmi() {
    local field="$1"
    local sysfs_file="$2"
    local val=""

    if command -v dmidecode >/dev/null 2>&1; then
        val=$(dmidecode -s "$field" 2>/dev/null || true)
    fi

    if [[ -z "$val" || "$val" =~ ^(None|To be filled|Not Specified|Default string)$ ]] && [[ -f "/sys/class/dmi/id/$sysfs_file" ]]; then
        val=$(cat "/sys/class/dmi/id/$sysfs_file" 2>/dev/null || true)
    fi

    if [[ -z "$val" ]]; then
        val="N/A"
    fi
    echo "$val"
}

# Determine default destination directory for forensic reports
detect_default_dir() {
    # 1. Search for mounted writeable target directories under /media/target
    if [[ -d "/media/target" ]]; then
        for target in /media/target/*; do
            if [[ -d "$target" && -w "$target" ]]; then
                echo "$target"
                return 0
            fi
        done
        if [[ -w "/media/target" ]]; then
            echo "/media/target"
            return 0
        fi
    fi

    # 2. Examiner desktop in live ISO
    local home_dir="${HOME:-/home/nixos}"
    if [[ -d "$home_dir/Desktop" && -w "$home_dir/Desktop" ]]; then
        echo "$home_dir/Desktop"
        return 0
    fi

    # 3. Fallback to user home
    if [[ -d "$home_dir" && -w "$home_dir" ]]; then
        echo "$home_dir"
        return 0
    fi

    # 4. Fallback to current working directory or /tmp
    if [[ -w "." ]]; then
        echo "."
    else
        echo "/tmp"
    fi
}

# Generate concise forensic triage report text (clean plain text, no ANSI codes)
generate_report() {
    local out_file="$1"
    local tmp_report
    tmp_report=$(mktemp)

    local host_clean
    host_clean=$(hostname 2>/dev/null || echo "dfnix-host")
    local ts_local
    ts_local=$(date "+%Y-%m-%d %H:%M:%S %Z")
    local ts_utc
    ts_utc=$(date -u "+%Y-%m-%d %H:%M:%S UTC")
    local kernel_ver
    kernel_ver=$(uname -srm)
    local boot_cmd
    boot_cmd=$(cat /proc/cmdline 2>/dev/null || echo "N/A")
    local user_info
    user_info="$(whoami) (UID: ${EUID:-$(id -u)})"
    local uptime_info
    uptime_info=$(uptime -p 2>/dev/null || uptime 2>/dev/null || echo "N/A")

    cat <<EOF > "$tmp_report"
================================================================================
DFNIX FORENSIC SYSTEM TRIAGE REPORT
================================================================================
Report Timestamp (Local):  ${ts_local}
Report Timestamp (UTC):    ${ts_utc}
Examiner Account:          ${user_info}
System Hostname:           ${host_clean}
Kernel Release:            ${kernel_ver}
Kernel Boot Parameters:    ${boot_cmd}
System Uptime:             ${uptime_info}
Environment:               dfnix Forensic Live Environment

================================================================================
1. SYSTEM PROFILE (FASTFETCH SUMMARY)
================================================================================
EOF

    # Capture uncolored, unlogoed fastfetch overview
    if command -v fastfetch >/dev/null 2>&1; then
        fastfetch --pipe --logo none 2>/dev/null >> "$tmp_report" || true
    else
        echo "fastfetch not available" >> "$tmp_report"
    fi

    cat <<EOF >> "$tmp_report"

================================================================================
2. DMI & FIRMWARE HARDWARE IDENTIFIERS
================================================================================
System Manufacturer:       $(get_dmi "system-manufacturer" "sys_vendor")
System Product Name:       $(get_dmi "system-product-name" "product_name")
System Serial Number:      $(get_dmi "system-serial-number" "product_serial")
System UUID:               $(get_dmi "system-uuid" "product_uuid")
System SKU / Family:       $(get_dmi "system-sku-number" "product_sku")
BIOS Vendor:               $(get_dmi "bios-vendor" "bios_vendor")
BIOS Version:              $(get_dmi "bios-version" "bios_version")
BIOS Release Date:         $(get_dmi "bios-release-date" "bios_date")
Baseboard Manufacturer:    $(get_dmi "baseboard-manufacturer" "board_vendor")
Baseboard Product:         $(get_dmi "baseboard-product-name" "board_name")
Baseboard Serial Number:   $(get_dmi "baseboard-serial-number" "board_serial")

================================================================================
3. ATTACHED STORAGE MEDIA & BLOCK DEVICES
================================================================================
EOF

    if command -v lsblk >/dev/null 2>&1; then
        lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MODEL,SERIAL,TRAN,RO,MOUNTPOINTS 2>/dev/null >> "$tmp_report" || true
    fi

    cat <<EOF >> "$tmp_report"

================================================================================
4. NETWORK INTERFACES & HARDWARE MAC ADDRESSES
================================================================================
EOF

    if command -v ip >/dev/null 2>&1; then
        echo "--- Physical / Logical Links (MAC) ---" >> "$tmp_report"
        ip -br link show 2>/dev/null >> "$tmp_report" || true
        echo "" >> "$tmp_report"
        echo "--- Assigned IP Addresses ---" >> "$tmp_report"
        ip -br addr show 2>/dev/null >> "$tmp_report" || true
    fi

    cat <<EOF >> "$tmp_report"

================================================================================
5. CONNECTED USB PERIPHERALS & CONTROLLERS
================================================================================
EOF

    if command -v lsusb >/dev/null 2>&1; then
        lsusb 2>/dev/null >> "$tmp_report" || true
    else
        echo "lsusb not available" >> "$tmp_report"
    fi

    cat <<EOF >> "$tmp_report"

================================================================================
6. KEY PCI CONTROLLERS & STORAGE BUSES
================================================================================
EOF

    if command -v lspci >/dev/null 2>&1; then
        {
            lspci 2>/dev/null | grep -E "VGA|3D|Display|Non-Volatile|SATA|SCSI|RAID|Ethernet|Network|USB" \
                || lspci 2>/dev/null \
                || true
        } >> "$tmp_report"
    else
        echo "lspci not available" >> "$tmp_report"
    fi

    cat <<EOF >> "$tmp_report"

================================================================================
7. CRYPTOGRAPHIC VERIFICATION & REPORT INTEGRITY
================================================================================
Generated File:    $(basename "$out_file")
Verification Note: Cryptographic SHA-256 digest is calculated over the entire final report.
                   See companion detached hash manifest: $(basename "$out_file").sha256
================================================================================
EOF

    # Move to final location
    mkdir -p "$(dirname "$out_file")"
    mv "$tmp_report" "$out_file"

    # Calculate SHA-256 over final complete file and create detached checksum manifest
    local sha256_hash
    sha256_hash=$(sha256sum "$out_file" | awk '{print $1}')
    (cd "$(dirname "$out_file")" && sha256sum "$(basename "$out_file")" > "$(basename "$out_file").sha256")

    # Ensure ownership is readable by standard live user if written to home
    if [[ "$out_file" == *"/home/nixos"* ]] && id nixos >/dev/null 2>&1; then
        chown nixos:users "$out_file" "${out_file}.sha256" 2>/dev/null || true
    fi

    echo "$sha256_hash"
}

# Display full interactive view
run_interactive() {
    clear
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║              dfinfo — Forensic System Triage & Fastfetch                     ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Visual Fastfetch display
    if command -v fastfetch >/dev/null 2>&1; then
        fastfetch || true
    else
        echo -e "${YELLOW}[!] fastfetch command not found.${NC}"
    fi

    echo ""
    echo -e "${CYAN}────────────────────────────────────────────────────────────────────────────────${NC}"
    echo -e " ${BOLD}[S]${NC} Save Forensic Triage (.txt)  ${BOLD}[V]${NC} View Storage & Hardware  ${BOLD}[Esc/Q]${NC} Exit"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────────────────────${NC}"

    while true; do
        read -rsn1 choice || true
        case "$choice" in
            s|S)
                echo ""
                local default_dir
                default_dir=$(detect_default_dir)
                local host_clean
                host_clean=$(hostname 2>/dev/null | tr -cd '[:alnum:]_-' || echo "host")
                local ts
                ts=$(date "+%Y%m%d_%H%M%S")
                local default_path="${default_dir}/system_triage_${host_clean}_${ts}.txt"

                echo -e "${CYAN}${BOLD}[*] Forensic Triage Export${NC}"
                echo -e "Default save path: ${GREEN}${default_path}${NC}"
                read -rp "Enter destination file path [Press ENTER for default]: " custom_path

                local target_file="${custom_path:-$default_path}"
                echo -e "${CYAN}[*] Compiling concise forensic report & computing SHA-256...${NC}"

                local hash
                hash=$(generate_report "$target_file")
                local fsize
                fsize=$(wc -c < "$target_file" 2>/dev/null || echo "0")

                echo ""
                echo -e "${GREEN}${BOLD}[✓] Forensic Triage Report successfully saved!${NC}"
                echo -e "    ${BOLD}Path:${NC}   $target_file"
                echo -e "    ${BOLD}Size:${NC}   $fsize bytes"
                echo -e "    ${BOLD}SHA256:${NC} $hash"
                echo -e "    ${BOLD}Hash Manifest:${NC} ${target_file}.sha256"
                echo ""
                read -rp "Press [Enter] or [Q] to exit..." _
                exit 0
                ;;
            v|V)
                clear
                echo -e "${CYAN}${BOLD}=== Storage Devices & Block Information ===${NC}"
                lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MODEL,SERIAL,TRAN,RO,MOUNTPOINTS || true
                echo ""
                echo -e "${CYAN}${BOLD}=== DMI / Hardware Identifiers ===${NC}"
                echo "System Manufacturer: $(get_dmi "system-manufacturer" "sys_vendor")"
                echo "System Product:      $(get_dmi "system-product-name" "product_name")"
                echo "System Serial:       $(get_dmi "system-serial-number" "product_serial")"
                echo "System UUID:         $(get_dmi "system-uuid" "product_uuid")"
                echo "BIOS Version:        $(get_dmi "bios-version" "bios_version") ($(get_dmi "bios-release-date" "bios_date"))"
                echo ""
                echo -e "${CYAN}${BOLD}=== Network Hardware (MACs) ===${NC}"
                ip -br link show || true
                echo ""
                echo -e "${CYAN}────────────────────────────────────────────────────────────────────────────────${NC}"
                echo -e " ${BOLD}[S]${NC} Save Forensic Triage (.txt)  ${BOLD}[Esc/Q]${NC} Exit"
                echo -e "${CYAN}────────────────────────────────────────────────────────────────────────────────${NC}"
                ;;
            q|Q|$'\e')
                echo ""
                exit 0
                ;;
        esac
    done
}

# Main CLI entrypoint
main() {
    local save_mode=false
    local print_mode=false
    local out_path=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -s|--save)
                save_mode=true
                shift
                ;;
            -o|--output)
                save_mode=true
                out_path="$2"
                shift 2
                ;;
            -p|--print)
                print_mode=true
                shift
                ;;
            -h|--help)
                echo -e "${BOLD}dfinfo${NC} — Forensic System Triage & Fastfetch Reporter"
                echo ""
                echo "Usage:"
                echo "  dfinfo                Launch interactive visual fastfetch with export prompt"
                echo "  dfinfo -s, --save     Generate and save concise forensic report without prompting"
                echo "  dfinfo -o <file>      Save forensic triage report directly to <file>"
                echo "  dfinfo -p, --print    Print clean plain-text forensic report to stdout"
                echo "  dfinfo -h, --help     Display this help documentation"
                exit 0
                ;;
            *)
                echo -e "${RED}[!] Unknown option: $1${NC}" >&2
                echo "Run 'dfinfo --help' for usage." >&2
                exit 1
                ;;
        esac
    done

    if [[ "$print_mode" == true ]]; then
        local tmp_f
        tmp_f=$(mktemp)
        generate_report "$tmp_f" >/dev/null
        cat "$tmp_f"
        rm -f "$tmp_f"
        exit 0
    fi

    if [[ "$save_mode" == true ]]; then
        if [[ -z "$out_path" ]]; then
            local default_dir
            default_dir=$(detect_default_dir)
            local host_clean
            host_clean=$(hostname 2>/dev/null | tr -cd '[:alnum:]_-' || echo "host")
            local ts
            ts=$(date "+%Y%m%d_%H%M%S")
            out_path="${default_dir}/system_triage_${host_clean}_${ts}.txt"
        fi

        echo -e "${CYAN}[*] Generating forensic triage report to: ${out_path}...${NC}"
        local hash
        hash=$(generate_report "$out_path")
        local fsize
        fsize=$(wc -c < "$out_path" 2>/dev/null || echo "0")

        echo -e "${GREEN}[✓] Report saved successfully.${NC}"
        echo -e "    File:   $out_path"
        echo -e "    Size:   $fsize bytes"
        echo -e "    SHA256:   $hash"
        echo -e "    Manifest: ${out_path}.sha256"
        exit 0
    fi

    run_interactive
}

main "$@"
