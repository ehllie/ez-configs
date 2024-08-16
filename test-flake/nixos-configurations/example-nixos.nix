# This is the module that will be imported with the `nixosConfigurations.example-nixos` system
{ config, ... }:
{
  fileSystems = {
    "/" = {
      device = "/dev/disk/by-uuid/FAKE-UUID";
      fsType = "ext4";
    };

    "/boot" = {
      device = "/dev/disk/by-uuid/FAKE-UUID";
      fsType = "vfat";
    };
  };
  swapDevices = [{ device = "/dev/vg1/swap"; }];

  users.users.system-user = rec {
    name = "alice";
    isNormalUser = true;
    home = "/home/${name}";
    description = "System User";
    extraGroups = [ "wheel" ];
    initialPassword = "password"; # Change this asap obv
  };

  nixpkgs.hostPlatform = "x86_64-linux";
}
