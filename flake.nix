{
  description = "A flake-parts module for simple nixos, darwin and home-manager configurations using project directory structure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
  };

  outputs = inputs: inputs.flake-parts.lib.mkFlake
    { inherit inputs; }
    {
      flake = {
        flakeModule = ./flake-module.nix;
        templates.default = {
          path = ./template;
          description = "A simple configuration template with ez-configs";
        };
      };
    };
}
