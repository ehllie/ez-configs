# This is the module that will be imported with the `homeManagerConfigurations.example-user@<system>` configuration
# You can use `ezModules` as a shorthand for accesing your flake's `homeConfigurations`
{ pkgs, ezModules, osConfig, ... }:
{
  imports = [
    ezModules.direnv
  ];

  home = {
    username = osConfig.users.users.example-user.name or "example-user";
    stateVersion = "22.05";
    homeDirectory = osConfig.users.users.example-user.home or (
      if pkgs.stdenv.isDarwin then
        "/Users/example-user" else
        "/home/example-user"
    );
  };
}
