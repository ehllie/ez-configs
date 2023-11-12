{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-23.05";
    nixpkgs-darwin.url = "github:NixOS/nixpkgs/nixpkgs-23.05-darwin";
    darwin = {
      url = "github:lnl7/nix-darwin/master";
      inputs.nixpkgs.follows = "nixpkgs-darwin";
    };
    home-manager = {
      # home-manager main branch is developed agains nixos-unstable,
      # so if you want to use a different nixos branch,
      # you need to use the appropriate home-manager branch.
      url = "github:nix-community/home-manager/release-23.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      inputs.nixpkgs-lib.follows = "nixpkgs";
    };
    ez-configs = {
      url = "github:ehllie/ez-configs";
      # We want to override the inputs of ez-configs
      # That way you're able to update your system packages when running `nix flake update`
      inputs = {
        nixpkgs.follows = "nixpkgs";
        nixpkgs-darwin.follows = "nixpkgs-darwin";
        flake-parts.follows = "flake-parts";
        darwin.follows = "darwin";
        home-manager.follows = "home-manager";
      };
    };
  };

  outputs = inputs@{ flake-parts, ez-configs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        ez-configs.flakeModule
      ];

      # mkFlake expects this to be present,
      # so even if we don't use anything from perSystem, we need to set it to something.
      # You can set it to anything you want if you also want to provide perSystem outputs in your flake.
      systems = [ ];

      ezConfigs = {
        root = ./.;
        globalArgs = { inherit inputs; };
      };
    };
}
