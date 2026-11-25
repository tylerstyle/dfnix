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

---

## GPU-Accelerated Forensic Tools (CUDA)

> **Research TODO. Nothing here is decided or implemented.** Each point is a question to answer before any tool is packaged.

- **Candidate uses**
  - Speech-to-text for audio and video evidence (interviews, voice messages, call recordings).
  - Translation of foreign-language text and transcripts.
  - Image recognition and media triage (classifying, grouping and prioritising large picture and video sets).
  - OCR of scans, screenshots and photographed documents.
- **Questions to answer per tool**
  - **Offline operation.** The live system works without a network. Model weights have to be on the medium or on a prepared data stick: how large are they, where do they come from, and how is their integrity checked?
  - **Licences.** Of the tool, of each model's weights, and of the GPU libraries it needs. cuDNN is not redistributable in nixpkgs (`cudaPackages.cudnn`, cuDNN EULA) and cannot be part of an image that is passed on; which tools work without it, and which do not?
  - **How it finds CUDA.** A program built by Nix with CUDA support carries its libraries; a Python wheel brings its own and needs only the driver; a prebuilt binary expects them on the system. Which of these applies decides whether the tool needs anything beyond the driver.
  - **Build cost.** nixpkgs does not serve CUDA builds from its binary cache. What has to be compiled, for how long, and can the result be cached?
  - **Memory.** The live system runs from RAM (`copytoram`), so image size is RAM. How much RAM and how much GPU memory does each model need, and what is left for acquisition?
  - **Evidential value.** Model output is a lead, not a finding: how are tool, model version, parameters and the hash of the input recorded so that a result can be reproduced and is not mistaken for a verified transcript or identification?
  - **Without a GPU.** Does the tool still work, slower, on the CPU, so that the standard image can offer it too?
- **Out of scope until this research is done:** packaging any of these tools, adding further CUDA libraries, and enabling CUDA support for nixpkgs as a whole.
