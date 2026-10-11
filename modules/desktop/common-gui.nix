# Graphics, keyboard layout, fonts, browsers and shell prompt shared by all desktops
{ pkgs, ... }: {
  hardware.graphics = {
    enable = true;
    enable32Bit = true;
  };

  services.xserver.xkb = {
    layout = "de,us";
    options = "grp:alt_shift_toggle";
  };

  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    nerd-fonts.fira-code
    nerd-fonts.symbols-only
  ];

  environment.systemPackages = with pkgs; [
    firefox
    chromium
  ];

  programs.starship = {
    enable = true;
    presets = [ ];
  };
  programs.bash.completion.enable = true;
}
