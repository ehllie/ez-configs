# This is the module that will be imported with the `homeManagerConfigurations.example-user@<system>` configuration
{ pkgs, ... }:
{
  home = {
    username = "example-user";
    stateVersion = "22.05";
    homeDirectory = if pkgs.stdenv.isDarwin then "/Users/example-user" else "/home/example-user";
  };
}
