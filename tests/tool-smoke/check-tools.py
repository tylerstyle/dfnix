#!/usr/bin/env python3
"""Run every binary in forensic packages with --help and flag startup failures.

A binary "passes" when it prints usage or runs without interpreter errors,
missing module/library errors, segfaults, or hangs.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from concurrent.futures import ThreadPoolExecutor

FAIL_PATTERNS = [
    r"bad interpreter",
    r"ModuleNotFoundError",
    r"ImportError",
    r"No module named",
    r"cannot open shared object",
    r"error while loading shared libraries",
    r"symbol lookup error",
    r"Can't locate \S+ in @INC",
    r"Segmentation fault",
    r"core dumped",
    r"command not found",
    r"Traceback \(most recent call last\)",
    r"not a valid Win32",
    r"exec format error",
    r"GLIBC_\d",
    r"version `\S+' not found",
    r"Could not find the Qt platform plugin",
    r"java\.lang\.\w+Error",
]
FAIL_RE = re.compile("|".join(FAIL_PATTERNS))

# Explicit skip list keyed by "<pname>/<binary>" with justified reasons:
SKIP_LIST = {
    # dfnet inner wrapper script using #!/usr/bin/env bash
    "dfnet/dfnet-cli": (
        "#!/usr/bin/env bash inner script; works on the ISO, which has /usr/bin/env, "
        "not in the Nix sandbox. Fix in the dfnet repo's package.nix: bash in buildInputs, "
        "so patchShebangs rewrites it."
    ),
    "dfnet/df-net": (
        "Symlink to dfnet-cli (#!/usr/bin/env bash inner script; works on the ISO, "
        "which has /usr/bin/env, not in the Nix sandbox)."
    ),

    # Zeek cluster & compiler tools
    "zeek/zeekctl": "Zeek cluster manager; requires cluster topology configuration (zeekctl.cfg).",
    "zeek/zeek-client": "Zeek controller client; requires active daemon and websocket module.",
    "zeek/spicy-precompile-headers": "Spicy compiler utility; hangs waiting on compiler inputs.",

    # Domain-specific tools requiring external infrastructure
    "samba/samba-gpupdate": "Active Directory Group Policy client; requires joined Active Directory domain.",

    # Hardware interactive utilities
    "sedutil/linuxpba": "TCG Opal PBA boot utility; interactively prompts on terminal for drive passphrase.",

    # MariaDB server scripts packaged as dangling links in mariadb-client
    "mariadb-client/mariadb-access": "Dangling upstream link to server-only script in mariadb-client.",
    "mariadb-client/mariadb-convert-table-format": "Dangling upstream link to server-only script in mariadb-client.",
    "mariadb-client/mariadb-dumpslow": "Dangling upstream link to server-only script in mariadb-client.",
    "mariadb-client/mariadb-find-rows": "Dangling upstream link to server-only script in mariadb-client.",
    "mariadb-client/mariadb-hotcopy": "Dangling upstream link to server-only script in mariadb-client.",
    "mariadb-client/mariadb-setpermission": "Dangling upstream link to server-only script in mariadb-client.",
    "mariadb-client/mysqlaccess": "Dangling upstream link to server-only script in mariadb-client.",
    "mariadb-client/mysql_convert_table_format": "Dangling upstream link to server-only script in mariadb-client.",
    "mariadb-client/mysql_find_rows": "Dangling upstream link to server-only script in mariadb-client.",
    "mariadb-client/mysqlhotcopy": "Dangling upstream link to server-only script in mariadb-client.",
    "mariadb-client/mysql_setpermission": "Dangling upstream link to server-only script in mariadb-client.",
    "mariadb-client/mysqldumpslow": "Dangling upstream link to server-only script in mariadb-client.",

    # MariaDB interactive server setup scripts & perl scripts
    "mariadb-client/mariadb-secure-installation": "Interactive MySQL server setup wizard; ignores --help and prompts for password.",
    "mariadb-client/mysql_secure_installation": "Interactive MySQL server setup wizard; ignores --help and prompts for password.",
    "mariadb-client/mytop": "MariaDB client Perl script with upstream Nixpkgs wrapper missing Perl in PATH.",
}


def run_binary(job):
    pname, bin_name, path, home = job
    key = f"{pname}/{bin_name}"

    if pname == "zeek" and bin_name.startswith("btest"):
        return {
            "pname": pname,
            "bin": bin_name,
            "path": path,
            "rc": 0,
            "status": "skip",
            "line": "SKIPPED: Zeek internal test suite harness.",
        }

    if key in SKIP_LIST:
        return {
            "pname": pname,
            "bin": bin_name,
            "path": path,
            "rc": 0,
            "status": "skip",
            "line": f"SKIPPED: {SKIP_LIST[key]}",
        }

    env = {
        "PATH": os.path.dirname(path) + ":" + os.environ.get("SMOKE_BASE_PATH", ""),
        "HOME": home,
        "XDG_CONFIG_HOME": os.path.join(home, ".config"),
        "XDG_CACHE_HOME": os.path.join(home, ".cache"),
        "XDG_DATA_HOME": os.path.join(home, ".local/share"),
        "TMPDIR": home,
        "TERM": "dumb",
        "LANG": "C.UTF-8",
        "QT_QPA_PLATFORM": "offscreen",
    }
    try:
        p = subprocess.run(
            [path, "--help"],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            timeout=10,
            env=env,
            cwd=home,
        )
        out = (p.stdout + p.stderr).decode("utf-8", "replace")
        rc = p.returncode
    except subprocess.TimeoutExpired as e:
        out = ((e.stdout or b"") + (e.stderr or b"")).decode("utf-8", "replace")
        rc = "timeout"
    except OSError as e:
        out = str(e)
        rc = "oserror"

    m = FAIL_RE.search(out)
    status = "ok"
    if rc in ("timeout", "oserror") or (isinstance(rc, int) and (rc in (126, 127) or rc < 0)):
        status = "fail"
    if m:
        status = "fail"

    first = ""
    if m:
        line_start = out.rfind("\n", 0, m.start()) + 1
        line_end = out.find("\n", m.end())
        first = out[line_start: line_end if line_end != -1 else None].strip()
    elif status == "fail":
        first = out.strip().splitlines()[-1] if out.strip() else ""

    return {
        "pname": pname,
        "bin": bin_name,
        "path": path,
        "rc": rc,
        "status": status,
        "line": first[:300],
    }


def main():
    parser = argparse.ArgumentParser(description="Forensic tools startup smoke test")
    parser.add_argument("--pkgs", required=True, help="JSON file containing list of {pname, path}")
    parser.add_argument("--out", required=True, help="Output directory for test results")
    args = parser.parse_args()

    with open(args.pkgs, "r") as f:
        pkgs = json.load(f)

    os.makedirs(args.out, exist_ok=True)
    temp_base = tempfile.mkdtemp(prefix="smoke-tmp-")

    jobs = []
    try:
        for item in pkgs:
            pname = item["pname"]
            outpath = item["path"]
            bindir = os.path.join(outpath, "bin")
            if not os.path.isdir(bindir):
                continue
            for b in sorted(os.listdir(bindir)):
                if b.startswith("."):
                    continue
                path = os.path.join(bindir, b)
                if not (os.path.isfile(path) and os.access(path, os.X_OK)):
                    continue
                home = os.path.join(temp_base, re.sub(r"[^A-Za-z0-9._-]", "_", f"{pname}--{b}"))
                os.makedirs(home, exist_ok=True)
                jobs.append((pname, b, path, home))

        workers = min(16, os.cpu_count() or 4)
        with ThreadPoolExecutor(max_workers=workers) as ex:
            results = list(ex.map(run_binary, jobs))
    finally:
        shutil.rmtree(temp_base, ignore_errors=True)

    results_file = os.path.join(args.out, "results.json")
    with open(results_file, "w") as f:
        json.dump(results, f, indent=1)

    fails = [r for r in results if r["status"] == "fail"]
    skips = [r for r in results if r["status"] == "skip"]
    passes = [r for r in results if r["status"] == "ok"]

    matched_keys = {r["pname"] + "/" + r["bin"] for r in skips}
    stale_skips = sorted(set(SKIP_LIST.keys()) - matched_keys)
    for k in stale_skips:
        print(f"stale skip: {k}")

    print(
        f"==> Tool smoke check: {len(results)} binaries from {len(pkgs)} packages "
        f"({len(passes)} passed, {len(skips)} skipped, {len(fails)} failed)"
    )

    if fails:
        print("\nStartup failures detected:")
        for r in fails:
            print(f"  FAIL {r['pname']:<32} {r['bin']:<28} rc={r['rc']}  {r['line']}")
        sys.exit(1)

    success_file = os.path.join(args.out, "success")
    with open(success_file, "w") as f:
        f.write("ok\n")
    print("==> All forensic tool binaries passed smoke check.")


if __name__ == "__main__":
    main()
