"""Exclusive opens (O_EXCL) of block devices, for the dfnix CFTT test.

An O_EXCL open of a block device takes the same claim a mounted filesystem,
a device-mapper table or an md array takes: while one exists, every other
exclusive open fails with EBUSY, while plain opens (readers) still succeed.

  cftt-excl probe DEVICE
      Claim DEVICE and release it at once. Exit 0, or 1 when it is claimed.
  cftt-excl hold DEVICE READY
      Claim DEVICE, create the file READY and keep the claim until killed.
  cftt-excl during TOOL DEVICE LOG COMMAND [ARG]...
      Run COMMAND. As soon as a process named TOOL has DEVICE open, try to
      claim DEVICE and check that TOOL still reads it afterwards; write what
      was seen to LOG. Exit with COMMAND's exit status.
"""

import errno
import os
import subprocess
import sys
import time


def claim(device):
    """An O_EXCL descriptor of `device`, or None when it is claimed."""
    try:
        return os.open(device, os.O_RDONLY | os.O_EXCL)
    except OSError as e:
        if e.errno == errno.EBUSY:
            return None
        raise


def readers(tool, node):
    """PIDs of the processes named `tool` that have `node` open."""
    found = []
    for pid in filter(str.isdigit, os.listdir("/proc")):
        try:
            with open(f"/proc/{pid}/comm") as f:
                if f.read().strip() != tool:
                    continue
            fds = os.listdir(f"/proc/{pid}/fd")
        except OSError:
            continue
        for fd in fds:
            try:
                if os.readlink(f"/proc/{pid}/fd/{fd}") == node:
                    found.append(int(pid))
                    break
            except OSError:
                pass
    return found


def probe(device):
    fd = claim(device)
    if fd is None:
        print(f"busy: {device} is claimed (EBUSY)")
        return 1
    os.close(fd)
    print(f"free: {device} could be claimed")
    return 0


def hold(device, ready):
    fd = claim(device)
    if fd is None:
        print(f"busy: {device} is claimed (EBUSY)", file=sys.stderr)
        return 1
    open(ready, "w").close()
    while True:
        time.sleep(3600)


def during(tool, device, log, command):
    node = os.path.realpath(device)
    child = subprocess.Popen(command)
    lines = []
    while child.poll() is None:
        seen = readers(tool, node)
        if seen:
            lines.append(f"reading: {tool} {seen} has {node} open")
            fd = claim(device)
            if fd is None:
                lines.append(f"busy: {device} cannot be claimed while {tool} reads it")
            else:
                os.close(fd)
                lines.append(f"free: {device} could be claimed while {tool} reads it")
            still = sorted(set(seen) & set(readers(tool, node)))
            lines.append(f"still reading: {still}")
            break
        time.sleep(0.05)
    else:
        lines.append(f"never saw {tool} reading {node}")
    status = child.wait()
    with open(log, "w") as f:
        f.write("\n".join(lines) + "\n")
    return status if status >= 0 else 128 - status


def main(argv):
    if len(argv) == 2 and argv[0] == "probe":
        return probe(argv[1])
    if len(argv) == 3 and argv[0] == "hold":
        return hold(argv[1], argv[2])
    if len(argv) >= 5 and argv[0] == "during":
        return during(argv[1], argv[2], argv[3], argv[4:])
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
