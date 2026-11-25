# NVIDIA's own driver and a CUDA runtime, for the second live image
# (profiles/live-nvidia.nix). Not part of the standard image.
#
# What is free and what is not:
# - the kernel modules (nvidia-open) are MIT / GPL-2.0-or-later;
# - the driver's userspace (libcuda, nvidia-smi, the OpenGL/Vulkan/OpenCL
#   libraries) and the GSP firmware are unfree, redistributable unmodified;
# - the CUDA libraries are unfree, redistributable under the CUDA EULA.
# cuDNN is not redistributable and is not here.
#
# The open kernel modules drive Turing (RTX 20, GTX 16) and newer cards only.
# With this driver enabled NixOS blacklists nouveau for every card, so an older
# NVIDIA card has no driver on this image and ends on the firmware framebuffer:
# those machines, and all machines without an NVIDIA card, take the standard
# image.
{ config, lib, pkgs, ... }:

let
  cuda = pkgs.cudaPackages;

  # The CUDA libraries a prebuilt program expects on the system: the runtime,
  # cuBLAS and the runtime compiler. A program built by Nix carries its own,
  # and a Python wheel brings its own; both need only the driver. More
  # libraries follow the tools that need them (IDEAS.md), not the other way
  # round.
  cudaLibraries = map lib.getLib [
    cuda.cuda_cudart
    cuda.libcublas
    cuda.cuda_nvrtc
  ];

  # One directory to point CUDA_PATH at, with the lib64 name that toolkit
  # layouts use
  cudaRuntime = pkgs.symlinkJoin {
    name = "dfnix-cuda-runtime-${cuda.cudaMajorMinorVersion}";
    paths = cudaLibraries;
    postBuild = ''
      ln -s lib "$out/lib64"
    '';
  };
in
{
  dfnix.release.variant = "nvidia";

  # The standard image keeps nouveau from binding to Blackwell cards with a
  # driver_override. That would keep NVIDIA's driver off them too.
  dfnix.hardware.blockBlackwellNouveau = false;

  services.xserver.videoDrivers = [ "nvidia" "modesetting" "fbdev" ];

  hardware.graphics.enable = true;
  hardware.nvidia = {
    open = true;
    package = config.boot.kernelPackages.nvidiaPackages.stable;
    # KMS, for the Wayland session and the console (nvidia-drm.modeset=1)
    modesetting.enable = true;
    # No settings GUI: it writes configuration, and there is nothing to tune
    nvidiaSettings = false;
  };

  # Only while the driver is on: a boot entry that turns it off (Safe
  # Graphics takes "nvidia" out of videoDrivers) gets no CUDA either
  hardware.graphics.extraPackages = lib.mkIf config.hardware.nvidia.enabled cudaLibraries;
  environment.variables = lib.mkIf config.hardware.nvidia.enabled {
    CUDA_PATH = "${cudaRuntime}";
  };
}
