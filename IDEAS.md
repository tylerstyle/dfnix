# dfnix — Future Ideas & Research

This document tracks prospective features, experimental concepts, and long-term architectural ideas for future exploration.

---

## Boot & Hardware Architecture

- **Secureboot workarounds**
  - Research and prototype a zero-touch or minimal-touch Secure Boot workflow for evidence systems.
  - Evaluate vendor-signed chainload stacks (e.g. Microsoft 3rd-Party-CA signed `shimx64.efi` + Canonical/Debian-signed `grubx64.efi` + signed vendor kernel with extracted signed modules).
  - Investigate persistent NVRAM side effects (such as `shim` writing `SbatLevel` to `EFI_VARIABLE_NON_VOLATILE`) versus forensic chain-of-custody requirements.
  - Assess Kernel Lockdown mode (`lockdown=integrity`) compatibility with forensic acquisition, `/dev/mem` restrictions, and kernel module signature enforcement.
  - Consider dual-artifact packaging: keeping the native pure-NixOS live ISO as the primary release while providing a dedicated, gated Secure Boot profile for specific field scenarios.
