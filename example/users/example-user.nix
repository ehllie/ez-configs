# This is the module that will be imported with the `homeManagerConfigurations.example-user@<system>` configuration
# You can use `ezModules` as a shorthand for accesing your flake's `homeConfigurations`
{ pkgs, ezModules, ... }:
{
  imports = [
    ezModules.direnv
  ];

  home = {
    username = "example-user";
    stateVersion = "22.05";
    homeDirectory = if pkgs.stdenv.isDarwin then "/Users/example-user" else "/home/example-user";
  };
}
