# Servers, hypervisors and containers

A server is often running, has more disks than a laptop, and may host virtual
machines or containers that matter more than the host itself. Decide early:
does the case need the running state (memory, connections, containers), or
can the server go down?

## 1. Before you touch it

- Ask the operator what runs on it. A shutdown can lose data the case needs:
  memory, encryption keys, containers that keep their filesystem only while
  running. It can also cause damage, for example with databases or a service
  others depend on.
- Note the hardware RAID controller, HBA, disks per bay, and BMC (iDRAC, iLO,
  XClarity, IPMI) with its address. Photograph the bays.
- Logs that live in RAM go first: ESXi keeps its logs on a ramdisk unless
  scratch or syslog is configured.

## 2. Running server (Linux or Windows)

Treat it as a running computer: `live-linux.md` or `live-windows.md` from the
field kit. Also:

- **Encrypted volumes:** keys (`dflive keys`) before anything else.
- **Databases:** a consistent logical dump with `dfcollect db postgres` or
  `dfcollect db mariadb` (the engine's own dump tools, the server's clock and
  settings recorded, the password never on a command line). Add the data files
  and WAL/binlog from the image later: deleted rows survive only there. For SQL
  Server and MongoDB see the roadmap §3.6.
- **Shares:** acquire what the order covers with `dfnet` (SMB/NFS, mounted
  read-only) and `dfcollect files`.
- **Volumes you can only get while running:** stream them with `dflive send`
  to `dfnet stream` on dfnix.

## 3. Powered-off server: imaging

- **Boot dfnix through the BMC's virtual media** (mount the ISO in the BMC's
  web UI), or from USB. Choose the "headless: serial console" boot entry: no
  graphical session; boot messages on COM2, where most BMCs redirect
  serial-over-LAN (iDRAC, iLO and Supermicro by default; check the BIOS's
  console redirection setting), and a login prompt on COM1 and COM2 at
  115200 baud. For work from a laptop,
  `dfnet ssh start --key case.pub --bind <address>` opens SSH with a per-case
  key until `dfnet ssh stop`. Netboot is planned.
- **Hardware RAID:** let the controller present the logical volume and image
  that with dfdisk. Read the member disks' serials and SMART through the
  controller with smartctl (`-d megaraid,N`, `-d cciss,N`, `-d aacraid,H,L,ID`).
  When time allows, image the members as well. `mdadm` reads the DDF and
  Intel IMSM metadata several controllers write, so those arrays can be rebuilt
  from the images.
- **Software RAID, LVM, ZFS, NAS:** image every member, then reassemble from
  the images, read-only: `raid-lvm-zfs.md`.
- **NVMe behind Intel VMD, SAS HBAs:** dfnix loads `vmd`, `megaraid_sas`,
  `mpt3sas`, `smartpqi`, `aacraid` and `hpsa` in the initrd. If disks are
  missing, check the BIOS RAID/VMD setting before changing anything.

## 4. VMware ESXi / vSphere (`govc` on dfnix)

```sh
export GOVC_URL='https://esxi-or-vcenter' GOVC_USERNAME='...' GOVC_PASSWORD='...'
export GOVC_INSECURE=1      # only after comparing the certificate fingerprint
govc ls /                                   # inventory
govc vm.info -json 'VM name' > vm-info.json # configuration, disks, snapshots
```

1. **Memory without touching the guest:** a snapshot with memory. The
   snapshot's `.vmsn`/`.vmem` hold the guest's RAM:
   `govc snapshot.create -vm 'VM name' -m=true -q=false 'case-01'`.
   This writes to the datastore: record it.
2. **Files:** list the VM's directory and download the `.vmx`, `.nvram`,
   `.vmsn`, `.vmem` and the whole VMDK chain (descriptor plus `-flat`/`-delta`
   files), then hash every file:
   `govc datastore.ls -ds DATASTORE -l 'VM name/'`, then
   `govc datastore.download -ds DATASTORE 'VM name/file' /media/target/case/vm/file`.
3. **Host artifacts:** `govc logs.download` (a support bundle with the host
   logs); UAC from the field kit for the host's own shell where ESXi allows it.
4. **Afterwards:** removing the snapshot consolidates the disks, which is
   another write. Agree with the operator whether it stays, and record either
   way.

`dissect` reads VMFS, VMDK and VHDX from images when you have the datastore
disks themselves.

## 5. Proxmox VE / KVM (libvirt)

On the host (record every command):

- **Memory:** `virsh dump --memory-only --format elf DOMAIN /path/mem.elf`
  (libvirt). On Proxmox: `qm monitor VMID`, then `dump-guest-memory
  /path/mem.elf`. Volatility reads the ELF. A snapshot with RAM (`qm snapshot
  VMID case01 --vmstate 1`) works too, but it writes to the VM storage.
- **Disks:** qcow2 files (`/var/lib/vz/images/VMID/`), LVM-thin volumes
  (`/dev/pve/vm-VMID-disk-N`) or ZFS zvols (`rpool/data/vm-VMID-disk-N`), with
  their snapshot chain. Copy them with hashing to a target, or stream a volume
  with `dflive send` to `dfnet stream` on dfnix. On dfnix, `qemu-img` and
  `qemu-nbd` (read-only, `-r`) open the images.

## 6. Hyper-V

Hyper-V defaults to *production* checkpoints (VSS inside the guest, no memory).
For memory:

1. `Get-VM 'Name' | Format-List CheckpointType` and note it.
2. `Set-VM -Name 'Name' -CheckpointType Standard`. This is a configuration
   change: record it, and set it back afterwards.
3. `Checkpoint-VM -Name 'Name' -SnapshotName 'case-01'`. The `.vmrs`/`.bin`
   files of the checkpoint hold the memory.
4. `Export-VMSnapshot` or `Export-VM` to a target, or copy the `.vhdx`/`.avhdx`
   chain. Offline: from the host volume, mounted read-only with dfmount.

## 7. Containers (Docker, containerd, Kubernetes)

A container's writable layer exists only while it isn't removed. Before
anyone stops anything:

- **Docker:**
  - `docker ps -a --no-trunc` and `docker inspect ID` (configuration, mounts,
    network);
  - `docker logs --timestamps ID`;
  - `docker diff ID` (what changed against the image);
  - `docker export ID > container.tar` (the filesystem as it is now);
  - the volumes (`docker inspect` names their paths).
- **Kubernetes:**
  - `kubectl get pod NAME -o yaml`;
  - `kubectl logs NAME --all-containers --timestamps`;
  - `kubectl get events`;
  - the node's container runtime (`crictl ps -a`, `crictl inspect`) for the
    same data on the node.
- Hash every file you take. Don't `exec` into containers unless the case needs
  it; it starts processes in the container.

## 8. NAS appliances (Synology, QNAP, …)

- **Running:** UAC from the field kit over the NAS's SSH, with its output on a
  target; shares via dfnet and `dfcollect files`. The NAS logs every login.
- **Off:** image every member and reassemble from the images
  (`raid-lvm-zfs.md`). Synology SHR is md + LVM; QNAP is md + LVM thin.

## Record

The controller, disks per bay with serials, and the BMC. Every command you ran
on the server or hypervisor, with its time. Every snapshot or checkpoint you
created or removed, and every configuration you changed and set back. Hashes of
all files you took.
