#!/usr/bin/env python3
"""
Desktop commands and pinned items validator for dfnix.
Verifies that all commands and pinned launcher desktop IDs used by Noctalia,
Niri, and installed desktop entries are registered in the provider map and installed
in environment.systemPackages.
"""

import argparse
import json
import os
import re
import shlex
import sys
import tomllib

ALWAYS_PRESENT = {
    # Standard shell interpreters present on POSIX / NixOS
    "sh",
    "bash",
    # Setuid wrapper provided by NixOS in /run/wrappers/bin/sudo (not in systemPackages)
    "sudo",
    # Shell builtins or core utilities guaranteed by coreutils in the base system
    "exec",
    "true",
    "echo",
    "sleep",
    "wait",
    "exit",
    "cat",
}

KITTY_OPTIONS_WITH_ARG = {
    "-o",
    "--override",
    "--class",
    "--name",
    "-T",
    "--title",
    "-d",
    "--directory",
    "-c",
    "--config",
    "--session",
}

KITTY_FLAGS = {
    "-e",
    "--hold",
}


def resolve_command_tokens(tokens):
    cmds = []
    while tokens:
        t0 = tokens[0]
        # sudo: setuid wrapper, not in systemPackages; skip and check wrapped command
        if t0 == "sudo" or t0 == "exec":
            tokens.pop(0)
            continue
        # sh -c "subcommand": resolve subcommand inside -c
        if t0 == "sh" and len(tokens) >= 3 and tokens[1] == "-c":
            tokens.pop(0)  # sh
            tokens.pop(0)  # -c
            sub_str = tokens.pop(0)
            cmds.extend(resolve_command_string(sub_str))
            continue
        # kitty: terminal wrapper. kitty itself is an installed command to check!
        if t0 == "kitty":
            cmd = tokens.pop(0)
            if cmd not in ALWAYS_PRESENT:
                cmds.append(cmd)
            # consume kitty options
            while tokens and tokens[0].startswith("-"):
                opt = tokens.pop(0)
                if opt == "--":
                    break
                if opt in KITTY_FLAGS:
                    continue
                if "=" in opt:
                    continue
                if opt in KITTY_OPTIONS_WITH_ARG:
                    if tokens:
                        tokens.pop(0)
            continue
        # Regular command
        cmd = tokens.pop(0).strip().rstrip(";").rstrip("}")
        if cmd and cmd not in ALWAYS_PRESENT:
            cmds.append(cmd)
        break
    return cmds


def resolve_command_string(s):
    s = s.replace('\\"', '"')
    # strip freedesktop field codes (%U, %f, etc.)
    s = re.sub(r"%[a-zA-Z]", "", s).strip()
    cmds = []
    s_clean = s.strip()

    if s_clean.startswith("sh -c") or s_clean.startswith('"sh" "-c"'):
        try:
            tokens = shlex.split(s_clean)
        except Exception:
            tokens = s_clean.split()
        return resolve_command_tokens(tokens)

    parts = re.split(r"&&|\|\||;|\|", s_clean)
    for p in parts:
        p = p.strip()
        if not p:
            continue
        p = re.sub(r"[0-9]?>[&]?[^\s]+", "", p).strip()
        if not p:
            continue
        try:
            tokens = shlex.split(p)
        except Exception:
            tokens = p.split()
        cmds.extend(resolve_command_tokens(tokens))
    return cmds


def main():
    parser = argparse.ArgumentParser(
        description="Verify desktop commands are present in system packages"
    )
    parser.add_argument(
        "--providers",
        required=True,
        help="JSON file mapping command/desktop ID to boolean installed status",
    )
    parser.add_argument(
        "--toml", required=True, help="Path to Noctalia config.toml"
    )
    parser.add_argument("--kdl", required=True, help="Path to Niri config.kdl")
    parser.add_argument(
        "--desktop-dir",
        required=False,
        help="Path to directory containing installed .desktop files",
    )
    parser.add_argument(
        "--tool-packages",
        nargs="*",
        default=[],
        help="df tool packages that must not ship a launcher dfnix already installs",
    )

    args = parser.parse_args()

    with open(args.providers, "r", encoding="utf-8") as f:
        providers = json.load(f)

    errors = []
    checked_items = []

    def check_item(name, source):
        checked_items.append((name, source))
        if name not in providers:
            errors.append(
                f"[-] MISSING PROVIDER: '{name}' (referenced in {source}) is not registered in tests/desktop-commands providers map."
            )
        elif not providers[name]:
            errors.append(
                f"[-] NOT INSTALLED: '{name}' (referenced in {source}) provider is NOT installed in environment.systemPackages (exit 127 regression!)."
            )

    # 1. Noctalia config.toml
    with open(args.toml, "rb") as f:
        toml_cfg = tomllib.load(f)

    # Pinned launcher applications
    pinned = toml_cfg.get("shell", {}).get("launcher", {}).get("pinned", [])
    for desktop_id in pinned:
        check_item(desktop_id, "Noctalia launcher.pinned")

    # Widget actions
    for wname, wcfg in toml_cfg.get("widget", {}).items():
        if isinstance(wcfg, dict):
            for aname, act in wcfg.get("actions", {}).items():
                if isinstance(act, str):
                    for cmd in resolve_command_string(act):
                        check_item(cmd, f"Noctalia widget.{wname}.actions.{aname}")

    # 2. Niri config.kdl
    with open(args.kdl, "r", encoding="utf-8") as f:
        kdl_text = f.read()

    for line in kdl_text.splitlines():
        line = line.strip()
        if not line or line.startswith("//"):
            continue

        m_startup = re.search(r"spawn-at-startup\s+(.*)", line)
        if m_startup:
            arg_str = re.sub(r"[\s;\}]+$", "", m_startup.group(1)).strip()
            tokens = shlex.split(arg_str)
            for c in resolve_command_tokens(tokens):
                if c not in ALWAYS_PRESENT:
                    check_item(c, "Niri spawn-at-startup")
            continue

        m_spawn_sh = re.search(r"spawn-sh\s+(.*)", line)
        if m_spawn_sh:
            arg_str = re.sub(r"[\s;\}]+$", "", m_spawn_sh.group(1)).strip()
            tokens = shlex.split(arg_str)
            if tokens:
                for c in resolve_command_string(tokens[0]):
                    check_item(c, "Niri spawn-sh")
            continue

        m_spawn = re.search(r"spawn\s+(.*)", line)
        if m_spawn:
            arg_str = re.sub(r"[\s;\}]+$", "", m_spawn.group(1)).strip()
            tokens = shlex.split(arg_str)
            for c in resolve_command_tokens(tokens):
                if c not in ALWAYS_PRESENT:
                    check_item(c, "Niri spawn")
            continue

    # 3. Installed desktop files in desktop-dir (linkFarm)
    launchers = set()
    if args.desktop_dir and os.path.isdir(args.desktop_dir):
        for root, _, files in os.walk(args.desktop_dir, followlinks=True):
            for file in sorted(files):
                if file.endswith(".desktop"):
                    launchers.add(file)
                    desktop_file = os.path.join(root, file)
                    with open(desktop_file, "r", encoding="utf-8", errors="replace") as f:
                        for line in f:
                            line = line.strip()
                            if line.startswith("Exec="):
                                exec_str = line[5:].strip()
                                for cmd in resolve_command_string(exec_str):
                                    check_item(cmd, f"desktop file {file} Exec=")

    # 4. Each launcher exists once: no df tool ships a copy of a dfnix launcher
    for pkg in args.tool_packages:
        apps = os.path.join(pkg, "share", "applications")
        if os.path.isdir(apps):
            for file in sorted(os.listdir(apps)):
                if file in launchers:
                    errors.append(
                        f"[-] DUPLICATE LAUNCHER: '{file}' is installed by dfnix and again by {pkg}."
                    )

    print(f"==> Checked {len(checked_items)} desktop commands and pinned IDs:")
    for name, src in sorted(set(checked_items)):
        print(f"    ✓ {name:<25} ({src})")

    if errors:
        print("\n" + "=" * 70, file=sys.stderr)
        print("DESKTOP COMMAND VERIFICATION FAILED:", file=sys.stderr)
        for err in errors:
            print(f"  {err}", file=sys.stderr)
        print("=" * 70, file=sys.stderr)
        sys.exit(1)

    print("\nAll desktop commands and pinned IDs verified successfully.")


if __name__ == "__main__":
    main()
