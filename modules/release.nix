# Stamp the dfnix revision a system was built from into /etc/dfnix-release and
# system.configurationRevision; dfcore puts it into every audit record.
{ config, lib, ... }:

{
  options.dfnix.release.revision = lib.mkOption {
    type = lib.types.str;
    default = "unknown";
    example = "57af663";
    description = "Git revision of dfnix the system was built from (`<rev>-dirty` for uncommitted trees).";
  };

  config = {
    system.configurationRevision = config.dfnix.release.revision;
    environment.etc."dfnix-release".text = ''
      DFNIX_NAME=dfnix
      DFNIX_REVISION=${config.dfnix.release.revision}
      DFNIX_NIXOS_RELEASE=${config.system.nixos.release}
    '';
  };
}
