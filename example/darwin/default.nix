{ pkgs, lib, ... }:
{
  services.nix-daemon.enable = true;
  security.pam.enableSudoTouchIdAuth = true;

  environment = {
    pathsToLink = [ "/share/zsh" ];
    systemPackages = lib.attrValues {
      inherit (pkgs)
        zsh
        coreutils
        home-manager;
    };
  };

  nix = {
    extraOptions = "experimental-features = nix-command flakes";
    settings.trusted-users = [ "@admin" ];

    gc = {
      automatic = true;
      options = "--delete-older-than 7d";
      interval = { Hour = 3; Minute = 15; Weekday = 6; };
    };
  };
}
