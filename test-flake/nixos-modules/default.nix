# This is the default nixos module.
# It will be included with any nixos host configuration that has `importDefault = true`, which is the default
{ modulesPath, ... }:
{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  nix = {
    extraOptions = "experimental-features = nix-command flakes";
    settings.trusted-users = [ "@wheel" ];

    gc = {
      automatic = true;
      dates = "daily";
      options = "--delete-older-than 7d";
    };
  };

  boot = {
    blacklistedKernelModules = [ "pcspkr" ];
    plymouth.enable = true;

    loader = {
      efi.canTouchEfiVariables = true;
      timeout = 0;

      systemd-boot = {
        enable = true;
        configurationLimit = 3;
      };
    };
  };
}
