# Field examination systems (live ISO, VM appliances): passwordless examiner
# account with autologin, and no network or clock behaviour that could leak the
# examiner's identity or alter the suspect machine.
{
  users.users.nixos = {
    isNormalUser = true;
    extraGroups = [ "wheel" "disk" "storage" "networkmanager" "video" "audio" "input" ];
    description = "Forensic Field Examiner";
    initialHashedPassword = "";
  };
  users.users.root.initialHashedPassword = "";
  security.sudo.wheelNeedsPassword = false;

  dfnix.desktop.displayManager.autologin = true;
  dfnix.desktop.displayManager.autologinUser = "nixos";

  networking.networkmanager.enable = true;
  # Randomize MACs from the first connection attempt so the hardware MAC never reaches the network
  networking.networkmanager.wifi.macAddress = "random";
  networking.networkmanager.ethernet.macAddress = "random";
  systemd.services.NetworkManager-wait-online.enable = false;

  # No NTP: a sync puts the kernel in 11-minute mode, which writes system time to the suspect's RTC
  services.timesyncd.enable = false;

  time.timeZone = "Europe/Berlin";
  i18n.defaultLocale = "en_US.UTF-8";
  console.keyMap = "de";
}
