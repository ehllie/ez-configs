{
  description = "A flake-parts module for simple nixos, darwin and home-manager configurations using project directory structure";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };

    darwin = {
      url = "github:lnl7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs@{ flake-parts, self, ... }:
    let
      inherit (flake-parts.lib) importApply mkFlake;
      flakeModule = importApply ./flake-module.nix inputs;
    in
    mkFlake { inherit inputs; } {
      imports = [
        flakeModule
      ];

      systems = [ ];

      flake = {
        inherit flakeModule;

        templates.default = {
          path = ./example;
          description = "A simple configuration template with ez-configs";
        };
      };

      ezConfigs.root = ./example;
    };
}
