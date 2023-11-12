# flake-parts module for multi-system and multi-user configuration

ez-configs flake-parts module provides a flexible framework for managing configurations across multiple systems using nixosSystem, darwinSystem (nix-darwin), and homeManagerConfiguration (home-manager), as well as exporting individual modules.

## Overview

This module allows for defining configuration and module outputs in your flake, for use in nixos, nix-darwin and home-manager, using your directory structure.
This results in 6 directories the module can use:

- [nixosModules](https://flake.parts/options/ez-configs#opt-ezConfigs.nixos.modulesDirectory)
- [nixosHosts](https://flake.parts/options/ez-configs#opt-ezConfigs.nixos.hostsDirectory)
- [darwinModules](https://flake.parts/options/ez-configs#opt-ezConfigs.darwin.modulesDirectory)
- [darwinHosts](https://flake.parts/options/ez-configs#opt-ezConfigs.darwin.hostsDirectory)
- [homeModules](https://flake.parts/options/ez-configs#opt-ezConfigs.hm.modulesDirectory)
- [users](https://flake.parts/options/ez-configs#opt-ezConfigs.hm.usersDirectory)

Each `.nix` file, or a directory containing `default.nix` file gets included in the respective outputs.
When building configurations, the default module (ie. `<modulesDirectory>/default.nix` or `<modulesDirectory>/default/default.nix`) is imported, unless `importDefault` is set to `false` for that user or host configuration.
In case of home manager configurations, it also includes the `darwin` or `linux` modules depending on the system that configuration is built from.

## Usage

To your flake inputs add:

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

I'd recommend also making all of this flake's inputs follow your own, since you might prefer using a stable release of nixos.
See the [example directory](https://github.com/ehllie/ez-configs/blob/main/example/flake.nix) for a documented example on how to do that.
I also use this module in my [own dotfiles](https://github.com/ehllie/dotfiles/blob/main/flake.nix).

## TODO

- Allow for loading home manager as a nixos module when specified in user config, rather than creating a `homeManagerConfigurations` output
- Warn when configuring users or hosts that are not present in the directory tree.
