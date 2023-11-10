{ darwin, home-manager, nixpkgs, ... }: { lib, config, ... }:
let

  inherit (builtins) listToAttrs pathExists;
  inherit (nixpkgs.lib) mkOption types concatMap mapAttrsToList nixosSystem optionals;
  inherit (darwin.lib) darwinSystem;
  inherit (home-manager.lib) homeManagerConfiguration;
  cfg = config.ezConfigs;


  # Import a module of a given name if it exists.
  # First check for a `.nix` file, then a directory.
  importModule = name:
    let
      file = "${name}.nix";
      dir = "${name}";
    in
    if pathExists file then file
    else if pathExists dir then dir
    else { };

  # Generates an atterset of nixosConfigurations or darwinConfigurations.
  # systemBuilder: The function to use to build the system. i.e. nixosSystem or darwinSystem
  # defaultModule: The module to always include in the system. i.e. ./nixos or ./darwin
  # hosts: A list of host declarations. i.e. [ { host = "foo"; system = "aarch64-darwin"; } ... ]
  systemsWith = { systemBuilder, systemSuffix, defaultModules, hostsDirectory, specialArgs }: hosts:
    listToAttrs (map
      ({ name, arch }: {
        inherit name;
        value = systemBuilder {
          inherit specialArgs;
          system = "${arch}-${systemSuffix}";
          modules = defaultModules ++ [
            (importModule "${hostsDirectory}/${name}")
          ];
        };
      })
      hosts);

  # Combined list attrsets containing the hostname
  # and it's configuration for all nixos and darwin systems.
  allHosts = mapAttrsToList
    (host: systemConf: systemConf //
      { inherit host; })
    (config.flake.nixosConfigurations //
      config.flake.darwinConfigurations);

  # Creates home-manager confgurations for each user on each host.
  # Tries to import users/${user} for each user.
  # Conditionally imports home/darwin and home/linux based on the host system.
  userConfigs = { directory, usersDirectory, extraSpecialArgs }: users:
    listToAttrs (concatMap
      ({ host, pkgs, ... }:
        let
          inherit (pkgs.stdenv) isDarwin isLinux;
        in
        map
          ({ name }: {
            name = "${name}@${host}";
            value = homeManagerConfiguration {
              inherit pkgs extraSpecialArgs;
              modules = [ (importModule directory) (importModule "${usersDirectory}/${name}") ] ++
                optionals isDarwin [ (importModule "${directory}/darwin") (importModule "${usersDirectory}/darwin") ] ++
                optionals isLinux [ (importModule "${directory}/linux") (importModule "${usersDirectory}/linux") ];
            };
          })
          users)
      allHosts);

  hostDefinition.options = {
    name = mkOption {
      type = types.str;
      description = "The hostname of the system.";
    };

    arch = mkOption {
      type = types.enum [ "x86_64" "aarch64" ];
      description = "The architecture of the system.";
    };
  };

  userDefinition.options = {
    name = mkOption {
      type = types.str;
      description = "The name of the user.";
    };
  };

in
{
  options.ezConfigs = {
    root = mkOption {
      default = ./.;
      type = types.pathInStore;
      description = ''
        The root from which configuration modules should be searched. You most likely want this to be `./.` or `self`.
      '';
    };

    globalArgs = mkOption {
      default = { };
      type = types.attrsOf types.anything;
      description = ''
        Extra arguments to pass to all systems.
      '';
    };

    hm = {
      directory = mkOption {
        default = "${cfg.root}/home";
        type = types.pathInStore;
        description = ''
          The directory in which to look for home-manager configurations.
        '';
      };

      usersDirectory = mkOption {
        default = "${cfg.root}/users";
        type = types.pathInStore;
        description = ''
          The directory in which to look for user specific home-manager configurations.
        '';
      };

      extraSpecialArgs = mkOption {
        default = cfg.globalArgs;
        type = types.attrsOf types.anything;
        description = ''
          Extra arguments to pass to all home-manager configurations.
        '';
      };

      users = mkOption {
        default = [ ];
        type = types.listOf (types.submodule userDefinition);
        description = ''
          A list of user definitions to create home manager configurations for.
        '';
      };
    };

    nixos = {
      directory = mkOption {
        default = "${cfg.root}/nixos";
        type = types.pathInStore;
        description = ''
          The directory in which to look for nixos configurations.
        '';
      };

      specialArgs = mkOption {
        default = cfg.globalArgs;
        type = types.attrsOf types.anything;
        description = ''
          Extra arguments to pass to all nixos configurations.
        '';
      };

      hostsDirectory = mkOption {
        default = "${cfg.root}/hosts";
        type = types.pathInStore;
        description = ''
          The directory in which to look for host specific nixos configurations.
        '';
      };

      hosts = mkOption {
        default = [ ];
        type = types.listOf (types.submodule hostDefinition);
        description = ''
          A list of nixos host definitions to create configurations for.
        '';
      };
    };

    darwin = {
      directory = mkOption {
        default = "${cfg.root}/darwin";
        type = types.pathInStore;
        description = ''
          The directory in which to look for darwin configurations.
        '';
      };

      specialArgs = mkOption {
        default = cfg.globalArgs;
        type = types.attrsOf types.anything;
        description = ''
          Extra arguments to pass to all darwin configurations.
        '';
      };

      hostsDirectory = mkOption {
        default = "${cfg.root}/hosts";
        type = types.pathInStore;
        description = ''
          The directory in which to look for host specific darwin configurations.
        '';
      };

      hosts = mkOption {
        default = [ ];
        type = types.listOf (types.submodule hostDefinition);
        description = ''
          A list of darwin host definitions to create configurations for.
        '';
      };
    };
  };

  config.flake = {
    homeConfigurations = userConfigs
      {
        inherit (cfg.hm)
          directory
          usersDirectory
          extraSpecialArgs;
      }
      cfg.hm.users;

    nixosConfigurations = systemsWith
      {
        systemBuilder = nixosSystem;
        systemSuffix = "linux";
        defaultModules = [ (importModule "${cfg.nixos.directory}") ];
        inherit (cfg.nixos) hostsDirectory specialArgs;
      }
      cfg.nixos.hosts;

    darwinConfigurations = systemsWith
      {
        systemBuilder = darwinSystem;
        systemSuffix = "darwin";
        defaultModules = [ (importModule "${cfg.darwin.directory}") ];
        inherit (cfg.darwin) hostsDirectory specialArgs;
      }
      cfg.darwin.hosts;
  };
}
