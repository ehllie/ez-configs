# This is the module that will be imported with the `homeManagerConfigurations.example-user@<system>` configuration
# You can use `ezModules` as a shorthand for accesing your flake's `homeConfigurations`
{ pkgs, ezModules, osConfig, ... }:
let users = osConfig.users.users;
in
{
  imports = [
    ezModules.direnv
  ];

  home = rec {
    username =
      if (users ? system-user) then
        users.system-user.name else
        "example-user";
    stateVersion = "22.05";
    homeDirectory =
      if (users ? system-user) then
        users.system-user.home else
        (
          if pkgs.stdenv.isDarwin then
            "/Users/${username}" else
            "/home/${username}"
        );
  };
}
