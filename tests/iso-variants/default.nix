# The two live images are told apart where they must be and are the same
# where they must be. `check` evaluates only (it is part of `nix flake
# check`); `runtime` builds the NVIDIA image's graphics and CUDA libraries,
# which fetches unfree software from NVIDIA, and is built on request
# (`make test-nvidia`). Neither can show that a GPU works: there is none in a
# build sandbox.
{ pkgs, standard, nvidia }:

let
  inherit (pkgs) lib;
  s = standard.config;
  n = nvidia.config;

  names = c: map (p: p.name or "") c.hardware.graphics.extraPackages;
  hasCuda = c: lib.any (lib.hasPrefix "cuda") (names c) || c.environment.variables ? CUDA_PATH;
  release = c: c.environment.etc."dfnix-release".text;

  # A boot entry of the NVIDIA image that turns the driver off (Safe Graphics)
  # must be the standard image as far as the GPU goes: the nouveau block for
  # Blackwell cards back on, no NVIDIA driver, no CUDA
  safe = n.specialisation.safe-graphics.configuration or null;

  facts = [
    # Same medium label: system-device protection and scripts/flash.sh know the
    # live medium by it
    { ok = s.isoImage.volumeID == "DFNIX_LIVE" && n.isoImage.volumeID == "DFNIX_LIVE"; msg = "both images have the volume label DFNIX_LIVE"; }
    # Different file, menu label and stamp
    { ok = s.image.fileName == "dfnix-forensics.iso"; msg = "the standard image is dfnix-forensics.iso (is ${s.image.fileName})"; }
    { ok = n.image.fileName == "dfnix-forensics-nvidia.iso"; msg = "the NVIDIA image is dfnix-forensics-nvidia.iso (is ${n.image.fileName})"; }
    { ok = s.isoImage.appendToMenuLabel != n.isoImage.appendToMenuLabel && lib.hasInfix "NVIDIA" n.isoImage.appendToMenuLabel; msg = "the NVIDIA image says so in the boot menu"; }
    { ok = lib.hasInfix "\nDFNIX_VARIANT=standard\n" (release s); msg = "the standard image is stamped DFNIX_VARIANT=standard"; }
    { ok = lib.hasInfix "\nDFNIX_VARIANT=nvidia\n" (release n); msg = "the NVIDIA image is stamped DFNIX_VARIANT=nvidia"; }
    # The standard image: no NVIDIA driver, no CUDA, nouveau kept off Blackwell
    { ok = !s.hardware.nvidia.enabled && !(hasCuda s); msg = "the standard image has neither NVIDIA's driver nor CUDA"; }
    { ok = s.dfnix.hardware.blockBlackwellNouveau; msg = "the standard image keeps nouveau off Blackwell cards"; }
    # The NVIDIA image: the open modules, CUDA, and no driver_override that
    # would keep NVIDIA's driver off Blackwell cards as well
    { ok = n.hardware.nvidia.enabled && n.hardware.nvidia.open; msg = "the NVIDIA image uses the open kernel modules"; }
    { ok = hasCuda n && !(lib.any (lib.hasInfix "cudnn") (names n)); msg = "the NVIDIA image has the CUDA runtime and no cuDNN"; }
    { ok = !n.dfnix.hardware.blockBlackwellNouveau; msg = "the NVIDIA image does not set the Blackwell driver_override"; }
    { ok = lib.elem "nouveau" n.boot.blacklistedKernelModules; msg = "the NVIDIA image blacklists nouveau"; }
  ] ++ lib.optionals (safe != null) [
    { ok = !safe.hardware.nvidia.enabled && !(hasCuda safe); msg = "Safe Graphics on the NVIDIA image has neither NVIDIA's driver nor CUDA"; }
    { ok = safe.dfnix.hardware.blockBlackwellNouveau; msg = "Safe Graphics on the NVIDIA image keeps nouveau off Blackwell cards"; }
  ];

  failed = map (f: f.msg) (lib.filter (f: !f.ok) facts);
in
{
  check =
    assert lib.assertMsg (failed == [ ]) "iso-variants, not true:\n- ${lib.concatStringsSep "\n- " failed}";
    pkgs.runCommand "iso-variants-check" { } ''
      printf '%s\n' ${lib.escapeShellArgs (map (f: f.msg) facts)} > $out
    '';

  # What a program that expects CUDA on the system finds: the driver's libcuda
  # and the three CUDA libraries where NixOS puts GPU libraries
  # (/run/opengl-driver), the same libraries under CUDA_PATH, and nvidia-smi
  runtime = pkgs.runCommand "nvidia-runtime-check" {
    # What /run/opengl-driver links to at boot
    drivers = n.systemd.tmpfiles.settings.graphics-driver."/run/opengl-driver"."L+".argument;
    cudaPath = n.environment.variables.CUDA_PATH;
    systemPath = n.system.path;
  } ''
    for l in libcuda.so.1 libnvidia-ml.so.1 libcudart.so libcublas.so libnvrtc.so; do
      found=$(find -L "$drivers/lib" -maxdepth 1 -name "$l*" -type f | head -n 1)
      [ -n "$found" ] || { echo "no $l in $drivers/lib"; exit 1; }
      echo "$l: $found" >> $out
    done
    for l in libcudart.so libcublas.so libnvrtc.so; do
      for d in lib lib64; do
        ls -L "$cudaPath/$d/$l"* > /dev/null || { echo "no $l in $cudaPath/$d"; exit 1; }
      done
    done
    [ -x "$systemPath/bin/nvidia-smi" ] || { echo "no nvidia-smi on the system path"; exit 1; }
    echo "nvidia-smi: $systemPath/bin/nvidia-smi" >> $out
    if find -L "$drivers/lib" "$cudaPath/lib" -name 'libcudnn*' | grep -q .; then
      echo "cuDNN is in the image"; exit 1
    fi
  '';
}
