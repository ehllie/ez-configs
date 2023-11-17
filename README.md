# flake-parts module for multi-system and multi-user configuration

ez-configs flake-parts module provides a flexible framework for managing configurations across multiple systems using nixosSystem, darwinSystem (nix-darwin), and homeManagerConfiguration (home-manager), as well as exporting individual modules.

## Overview

This module allows for defining configuration and module outputs in your flake, for use in nixos, nix-darwin and home-manager, using your directory structure.
This results in 6 directories the module can use:

- [nixosModules](https://flake.parts/options/ez-configs#opt-ezConfigs.nixos.modulesDirectory)
- [nixosConfigurations](https://flake.parts/options/ez-configs#opt-ezConfigs.nixos.configurationsDirectory)
- [darwinModules](https://flake.parts/options/ez-configs#opt-ezConfigs.darwin.modulesDirectory)
- [darwinConfigurations](https://flake.parts/options/ez-configs#opt-ezConfigs.darwin.configurationsDirectory)
- [homeModules](https://flake.parts/options/ez-configs#opt-ezConfigs.home.modulesDirectory)
- [homeConfigurations](https://flake.parts/options/ez-configs#opt-ezConfigs.home.configurationsDirectory)

Each `.nix` file, or a directory containing `default.nix` file gets included in the respective outputs.
When building configurations, the default module (ie. `<modulesDirectory>/default.nix` or `<modulesDirectory>/default/default.nix`) is imported, unless `importDefault` is set to `false` for that user or host configuration.
In case of home manager configurations, it also includes the `darwin` or `linux` modules depending on the system that configuration is built from.

## Usage

If starting from scratch, you can use the template `nix flake new --template github:ehllie/ez-configs` inside the directory where you'd like to setup your flake.

Otherwise, to your flake inputs add:

```nix
ez-configs.url = "github:ehllie/ez-configs";
```

Inside your mkFlake add:

```nix
imports = [
  inputs.ez-configs.flakeModule
];

ezConfigs.root = ./.;

```

I also use this module in my [own dotfiles](https://github.com/ehllie/dotfiles/blob/main/flake.nix).
