# This is the module that will be imported with the `nixosConfigurations.example-nixos` system
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

  users.users.example-user = {
    isNormalUser = true;
    home = "/home/example-user";
    description = "Example User";
    extraGroups = [ "wheel" ];
    initialPassword = "password"; # Change this asap obv
  };

  nixpkgs.hostPlatform = "x86_64-linux";
}
