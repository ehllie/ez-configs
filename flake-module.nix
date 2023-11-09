{ darwin, home-manager, ... }: inputs@{ lib, config, ... }:
let

  inherit (builtins) listToAttrs pathExists;
  inherit (lib) mkOption types concatMap mapAttrsToList nixosSystem optionals;
  inherit (darwin.lib) darwinSystem;
  inherit (home-manager.lib) homeManagerConfiguration;
  cfg = config.ezConfigs;


  # Import a module of a given name if it exists.
  # First check for a `.nix` file, then a directory.
  importModule = name:
    let
      file = cfg.root + "/${name}.nix";
      dir = cfg.root + "/${name}";
    in
    if pathExists file then file
    else if pathExists dir then dir
    else { };

  # Generates an atterset of nixosConfigurations or darwinConfigurations.
  # systemBuilder: The function to use to build the system. i.e. nixosSystem or darwinSystem
  # defaultModule: The module to always include in the system. i.e. ./nixos or ./darwin
  # hosts: A list of host declarations. i.e. [ { host = "foo"; system = "aarch64-darwin"; } ... ]
  systemsWith = { systemBuilder, systemSuffix, defaultModules, hostsDirectory }: hosts:
    listToAttrs (map
      ({ name, arch }: {
        inherit name;
        value = systemBuilder {
          system = "${arch}-${systemSuffix}";
          specialArgs = { inherit inputs; };
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
    (config.nixosConfigurations //
      config.darwinConfigurations);

  # Creates home-manager confgurations for each user on each host.
  # Tries to import users/${user} for each user.
  # Conditionally imports home/darwin and home/linux based on the host system.
  userConfigs = users:
    listToAttrs (concatMap
      ({ host, pkgs, ... }:
        let
          inherit (pkgs.stdenv) isDarwin isLinux;
        in
        map
          ({ name }: {
            name = "${name}@${host}";
            value = homeManagerConfiguration {
              inherit pkgs;
              extraSpecialArgs = { inherit inputs; };
              modules = [ ./home (importModule "${cfg.hm.directory}/${name}") ] ++
                optionals isDarwin [ (importModule "${cfg.hm.directory}/darwin") ] ++
                optionals isLinux [ (importModule "${cfg.hm.directory}/linux") ];
            };
          })
          users)
      allHosts);

  hostDefinition.options = {
    name = mkOption {
      type = types.string;
      description = "The hostname of the system.";
    };

    arch = mkOption {
      type = types.enum [ "x86_64" "aarch64" ];
      description = "The architecture of the system.";
    };
  };

  userDefinition.options = {
    name = mkOption {
      type = types.string;
      description = "The name of the user.";
    };
  };

in
{
  options.ezConfigs = {
    root = mkOption {
      type = types.pathInStore;
      description = ''
        The root from which configuration modules should be searched. You most likely want this to be `./.` or `self`.
      '';
    };

    hm = {
      directory = mkOption {
        default = "home";
        type = types.string;
        description = ''
          The directory in which to look for home-manager configurations.
        '';
      };

      users = mkOption {
        default = [ ];
        type = types.listOf (types.submodule userDefinition);
      };
    };

    nixos = {
      directory = mkOption {
        default = "nixos";
        type = types.string;
        description = ''
          The directory in which to look for nixos configurations.
        '';
      };

      hostDirectory = mkOption {
        default = "hosts";
        type = types.string;
        description = ''
          The directory in which to look for host specific nixos configurations.
        '';
      };

      hosts = mkOption {
        default = [ ];
        type = types.listOf (types.submodule hostDefinition);
      };
    };

    darwin = {
      directory = mkOption {
        default = "darwin";
        type = types.string;
        description = ''
          The directory in which to look for darwin configurations.
        '';
      };


      hostDirectory = mkOption {
        default = "hosts";
        type = types.string;
        description = ''
          The directory in which to look for host specific darwin configurations.
        '';
      };

      hosts = mkOption {
        default = [ ];
        type = types.listOf (types.submodule hostDefinition);
      };
    };
  };

  config.flake = {
    homeConfigurations = userConfigs cfg.hm.users;

    nixosConfigurations = systemsWith
      {
        systemBuilder = nixosSystem;
        systemSuffix = "linux";
        defaultModules = [ (importModule "${cfg.nixos.directory}") ];
        hostsDirectory = cfg.nixos.hostDirectory;
      }
      cfg.nixos.hosts;

    darwinConfigurations = systemsWith
      {
        systemBuilder = darwinSystem;
        systemSuffix = "darwin";
        defaultModules = [ (importModule "${cfg.darwin.directory}") ];
        hostsDirectory = cfg.darwin.hostDirectory;
      }
      cfg.darwin.hosts;
  };
}
