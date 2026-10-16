{ pkgs }:

let
  inherit (pkgs)
    attr
    e2fsprogs
    exfatprogs
    fieldkit
    gptfdisk
    hfsprogs
    jq
    kmod
    ntfs3g
    python3
    runCommand
    util-linux
    vmTools
    writeText
    ;

  verifyManifestPy = writeText "verify-fieldkit-manifest.py" ''
    import hashlib
    import json
    import os
    import stat
    import subprocess
    import sys

    manifest_path = sys.argv[1]
    mnt_root = sys.argv[2]

    with open(manifest_path, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    assert manifest["schema"] == "dfnix.fieldkit.manifest/v0", f"Unexpected schema: {manifest.get('schema')}"
    assert "image" in manifest and manifest["image"]["sha256"], "Missing top-level image hash in manifest.json"
    assert len(manifest["partitions"]) == 4, f"Expected 4 partitions, got {len(manifest['partitions'])}"

    def sha256_file(path):
        h = hashlib.sha256()
        with open(path, "rb") as f:
            while True:
                chunk = f.read(1024 * 1024)
                if not chunk:
                    break
                h.update(chunk)
        return h.hexdigest()

    total_verified_files = 0
    total_verified_symlinks = 0

    for part in manifest["partitions"]:
        label = part["label"]
        part_mnt = os.path.join(mnt_root, label)
        assert os.path.ismount(part_mnt), f"{part_mnt} is not mounted"

        actual_files = {}
        actual_symlinks = {}

        for root, dirs, files in os.walk(part_mnt, followlinks=False):
            # Ignore ext4 lost+found if present
            if root == part_mnt and "lost+found" in dirs:
                dirs.remove("lost+found")
            dirs.sort()
            for entry in sorted(dirs + files):
                full = os.path.join(root, entry)
                rel = os.path.relpath(full, part_mnt).replace(os.sep, "/")
                if os.path.islink(full):
                    actual_symlinks[rel] = os.readlink(full)
                elif os.path.isfile(full):
                    actual_files[rel] = full

        expected_files = {f["path"]: f for f in part["files"]}
        expected_symlinks = {s["path"]: s for s in part["symlinks"]}

        missing_files = set(expected_files.keys()) - set(actual_files.keys())
        extra_files = set(actual_files.keys()) - set(expected_files.keys())
        assert not missing_files, f"[{label}] Missing files on mounted partition: {sorted(missing_files)}"
        assert not extra_files, f"[{label}] Unexpected extra files on mounted partition: {sorted(extra_files)}"

        missing_links = set(expected_symlinks.keys()) - set(actual_symlinks.keys())
        extra_links = set(actual_symlinks.keys()) - set(expected_symlinks.keys())
        assert not missing_links, f"[{label}] Missing symlinks on mounted partition: {sorted(missing_links)}"
        assert not extra_links, f"[{label}] Unexpected extra symlinks on mounted partition: {sorted(extra_links)}"

        for rel, fmeta in expected_files.items():
            full = actual_files[rel]
            sz = os.path.getsize(full)
            digest = sha256_file(full)
            assert sz == fmeta["size"], f"[{label}] Size mismatch for {rel}: expected {fmeta['size']}, got {sz}"
            assert digest == fmeta["sha256"], f"[{label}] SHA-256 mismatch for {rel}: expected {fmeta['sha256']}, got {digest}"
            assert fmeta.get("package"), f"[{label}] Missing package provenance for {rel}"
            assert fmeta.get("version"), f"[{label}] Missing version provenance for {rel}"
            assert fmeta.get("license"), f"[{label}] Missing license provenance for {rel}"

            # Check read-only / immutable flags per filesystem
            if label == "KIT-WIN":
                raw_attr = os.getxattr(full, "system.ntfs_attrib_be")
                val = int.from_bytes(raw_attr, "big")
                assert (val & 0x1) == 0x1, f"[KIT-WIN] NTFS FILE_ATTRIBUTE_READONLY not set on {rel}: {raw_attr.hex()}"
            elif label in ("KIT-MAC", "KIT-LNX"):
                mode = os.stat(full).st_mode
                assert (mode & (stat.S_IWUSR | stat.S_IWGRP | stat.S_IWOTH)) == 0, (
                    f"[{label}] Write permission bit still set on {rel}: {oct(mode)}"
                )
                lsattr_out = subprocess.check_output(["lsattr", full], text=True).strip().split()[0]
                assert "i" in lsattr_out, f"[{label}] Immutable flag (+i) not set on {rel}: {lsattr_out}"

            total_verified_files += 1

        for rel, smeta in expected_symlinks.items():
            target = actual_symlinks[rel]
            assert target == smeta["target"], (
                f"[{label}] Symlink target mismatch for {rel}: expected {smeta['target']}, got {target}"
            )
            total_verified_symlinks += 1

        print(
            f"[OK] {label} ({part['filesystem']}): verified {len(expected_files)} files "
            f"and {len(expected_symlinks)} symlinks against manifest.json"
        )

    print(
        f"[OK] All 4 partitions verified ({total_verified_files} files, "
        f"{total_verified_symlinks} symlinks)."
    )
  '';
in
vmTools.runInLinuxVM (
  runCommand "fieldkit-check-${fieldkit.version}"
    {
      memSize = 1024;
      nativeBuildInputs = [
        attr
        e2fsprogs
        exfatprogs
        gptfdisk
        hfsprogs
        jq
        kmod
        ntfs3g
        python3
        util-linux
      ];
      postVM = ''
        mkdir -p "$out"
        cp xchg/verification-report.txt "$out/verification-report.txt"
      '';
    }
    ''
      set -euo pipefail

      exec > >(tee /tmp/xchg/verification-report.txt) 2>&1

      echo "=== 1. Verifying top-level image hash and manifest metadata ==="
      (
        cd "${fieldkit}"
        sha256sum -c fieldkit.img.sha256
      )
      expected_img_sha=$(jq -r '.image.sha256' "${fieldkit}/manifest.json")
      actual_img_sha=$(awk '{print $1}' "${fieldkit}/fieldkit.img.sha256")
      test "$expected_img_sha" = "$actual_img_sha"

      echo "=== 2. Attaching fieldkit.img read-only via loop device ==="
      modprobe loop
      loopdev=$(losetup -r -P -f --show "${fieldkit}/fieldkit.img")
      echo "Attached ${fieldkit}/fieldkit.img at $loopdev"
      test "$(blockdev --getro "$loopdev")" = "1"

      echo "=== 3. Checking GPT partition table (types, labels, attribute bit 60) ==="
      sgdisk -v "$loopdev"
      sgdisk -p "$loopdev"

      check_part() {
        local pnum="$1"
        local expected_guid="$2"
        local expected_name="$3"
        local expected_attr="$4"

        local info
        info=$(sgdisk -i "$pnum" "$loopdev")
        echo "$info"
        echo "$info" | grep -F "Partition GUID code: $expected_guid"
        echo "$info" | grep -F "Partition name: '$expected_name'"
        echo "$info" | grep -F "Attribute flags: $expected_attr"
      }

      check_part 1 "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7" "KIT-WIN" "1000000000000000"
      check_part 2 "48465300-0000-11AA-AA11-00306543ECAC" "KIT-MAC" "1000000000000000"
      check_part 3 "0FC63DAF-8483-4772-8E79-3D69D8477DE4" "KIT-LNX" "1000000000000000"
      check_part 4 "EBD0A0A2-B9E5-4433-87C0-68B6B72699C7" "KIT-OUT" "0000000000000000"

      echo "=== 4. Running read-only fsck on all 4 filesystems ==="
      echo "--- Partition 1 (KIT-WIN, NTFS): ntfsfix -n ---"
      ntfsfix -n "''${loopdev}p1"

      echo "--- Partition 2 (KIT-MAC, HFS+): fsck.hfsplus -n ---"
      fsck.hfsplus -n "''${loopdev}p2"

      echo "--- Partition 3 (KIT-LNX, ext4): e2fsck -n ---"
      e2fsck -n "''${loopdev}p3"

      echo "--- Partition 4 (KIT-OUT, exFAT): fsck.exfat -n ---"
      fsck.exfat -n "''${loopdev}p4"

      echo "=== 5. Mounting all 4 partitions read-only ==="
      mkdir -p /mnt/KIT-WIN /mnt/KIT-MAC /mnt/KIT-LNX /mnt/KIT-OUT
      ntfs-3g -o ro "''${loopdev}p1" /mnt/KIT-WIN
      mount -t hfsplus -o ro "''${loopdev}p2" /mnt/KIT-MAC
      mount -t ext4 -o ro,noload "''${loopdev}p3" /mnt/KIT-LNX
      mount -t exfat -o ro "''${loopdev}p4" /mnt/KIT-OUT

      echo "=== 6. Verifying per-partition KIT-MANIFEST.sha256 and required markers ==="
      for part in KIT-WIN KIT-MAC KIT-LNX; do
        echo "--- sha256sum -c /mnt/$part/KIT-MANIFEST.sha256 ---"
        (
          cd "/mnt/$part"
          sha256sum -c KIT-MANIFEST.sha256 > /dev/null
        )
        test -s "/mnt/$part/SOURCES.txt"
      done

      test -f /mnt/KIT-WIN/live-windows.md
      test -f /mnt/KIT-WIN/live-windows.txt
      test -f /mnt/KIT-MAC/live-macos.md
      test -f /mnt/KIT-LNX/live-linux.md
      test -f /mnt/KIT-MAC/.metadata_never_index
      test -f /mnt/KIT-MAC/.fseventsd/no_log
      test -f /mnt/KIT-OUT/.metadata_never_index
      test -f /mnt/KIT-OUT/.fseventsd/no_log

      echo "=== 7. Verifying UAC runs from its root directory on KIT-LNX and KIT-MAC ==="
      (cd /mnt/KIT-LNX/uac && ./uac --version) | grep -F "UAC (Unix-like Artifacts Collector)"
      (cd /mnt/KIT-MAC/uac && ./uac --version) | grep -F "UAC (Unix-like Artifacts Collector)"

      echo "=== 8. Verifying every file, symlink, and attribute against manifest.json ==="
      python3 "${verifyManifestPy}" "${fieldkit}/manifest.json" /mnt

      umount /mnt/KIT-WIN /mnt/KIT-MAC /mnt/KIT-LNX /mnt/KIT-OUT
      losetup -d "$loopdev"
      echo "=== Field-kit verification check PASSED ==="
    ''
)
