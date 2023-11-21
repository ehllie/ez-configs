# This is the module that will be imported with the `darwinConfigurations.example-darwin` system
{ pkgs, ... }:
{
  fonts = {
    fontDir.enable = true;
    fonts = [
      (pkgs.nerdfonts.override { fonts = [ "CascadiaCode" ]; })
    ];
  };

  users.users.example-user = {
    name = "example-user";
    home = "/Users/example-user";
  };

  nixpkgs.hostPlatform = "aarch64-darwin";
}
