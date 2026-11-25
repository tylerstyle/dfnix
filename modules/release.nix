# Stamp the dfnix revision a system was built from into /etc/dfnix-release and
# system.configurationRevision; dfcore puts it into every audit record. The
# variant says which of the images it is (dfcore does not read it yet).
{ config, lib, ... }:

{
  options.dfnix.release.revision = lib.mkOption {
    type = lib.types.str;
    default = "unknown";
    example = "57af663";
    description = "Git revision of dfnix the system was built from (`<rev>-dirty` for uncommitted trees).";
  };

  options.dfnix.release.variant = lib.mkOption {
    type = lib.types.enum [ "standard" "nvidia" ];
    default = "standard";
    description = ''
      Which image this system is: `standard` (free software only in the
      graphics stack) or `nvidia` (NVIDIA's open kernel modules with their
      unfree userspace and CUDA libraries).
    '';
  };

  config = {
    system.configurationRevision = config.dfnix.release.revision;
    environment.etc."dfnix-release".text = ''
      DFNIX_NAME=dfnix
      DFNIX_REVISION=${config.dfnix.release.revision}
      DFNIX_VARIANT=${config.dfnix.release.variant}
      DFNIX_NIXOS_RELEASE=${config.system.nixos.release}
    '';
  };
}
