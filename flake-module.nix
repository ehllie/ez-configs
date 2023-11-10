{ darwin, home-manager, nixpkgs, ... }: { lib, config, ... }:
let

  inherit (builtins) pathExists;
  inherit (nixpkgs.lib) mkOption types nixosSystem optionals literalExpression mapAttrs concatMapAttrs;
  inherit (darwin.lib) darwinSystem;
  inherit (home-manager.lib) homeManagerConfiguration;
  cfg = config.ezConfigs;


  # Import a module of a given name if it exists.
  # First check for a `.nix` file, then a directory.
  importModule = name:
    let
      file = "${name}.nix";
      dir = "${name}/default.nix";
    in
    if pathExists file then file
    else if pathExists dir then dir
    else { };

  # Creates an attrset of nixosConfigurations or darwinConfigurations.
  systemsWith = { systemBuilder, systemSuffix, modulesDirectory, hostsDirectory, specialArgs }: hosts:
    mapAttrs
      (name: { arch, importDefault }: systemBuilder {
        inherit specialArgs;
        system = "${arch}-${systemSuffix}";
        modules = [ (importModule "${hostsDirectory}/${name}") ]
          ++ optionals importDefault [ (importModule "${modulesDirectory}") ];
      })
      hosts;

  allHosts =
    (config.flake.nixosConfigurations //
      config.flake.darwinConfigurations);

  # Creates an attrset of home manager confgurations for each user on each host.
  userConfigs = { modulesDirectory, usersDirectory, extraSpecialArgs }: users:
    concatMapAttrs
      (user: { importDefault, nameFunction }:
        let
          mkName =
            if nameFunction == null
            then host: "${user}@${host}"
            else nameFunction;
        in
        concatMapAttrs
          (host: { pkgs, ... }:
            let
              inherit (pkgs.stdenv) isDarwin isLinux;
              name = mkName host;
            in
            {
              ${name} = homeManagerConfiguration {
                inherit pkgs extraSpecialArgs;
                modules = [ (importModule "${usersDirectory}/${user}") ] ++ # user module
                  optionals importDefault [ (importModule "${modulesDirectory}") ] ++ # default module
                  optionals isDarwin ([ (importModule "${usersDirectory}/${user}/darwin") ] ++ # user darwin module
                    optionals importDefault [ (importModule "${modulesDirectory}/darwin") ]) ++ # default darwin module
                  optionals isLinux ([ (importModule "${usersDirectory}/${user}/linux") ] ++ # user linux module
                    optionals importDefault [ (importModule "${modulesDirectory}/linux") ]); # default linux module
              };
            })
          allHosts)
      users;

  hostOptions.options = {
    arch = mkOption {
      type = types.enum [ "x86_64" "aarch64" ];
      description = "The architecture of the system.";
    };

    importDefault = mkOption {
      default = true;
      type = types.bool;
      description = ''
        Whether to import the default module for this host.
      '';
    };
  };

  userOptions.options = {
    nameFunction = mkOption {
      type = types.nullOr (types.functionTo types.str);
      default = null;
      defaultText = literalExpression "\${username}@\${hostname}";
      example = literalExpression "(host: \"\${host}-\${name})\")";
      description = ''
        Function to generate the name of the user configuration using the host name.
      '';
    };

    importDefault = mkOption {
      default = true;
      type = types.bool;
      description = ''
        Whether to import the default module for this user.
      '';
    };
  };

  hostsOptions = system: {
    modulesDirectory = mkOption {
      default = "${cfg.root}/${system}";
      defaultText = literalExpression "\"\${ezConfigs.root}/${system}\"";
      type = types.pathInStore;
      description = ''
        The directory in which to look for ${system} modules.
      '';
    };

    hostsDirectory = mkOption {
      default = "${cfg.root}/hosts";
      defaultText = literalExpression "\"\${ezConfigs.root}/hosts\"";
      type = types.pathInStore;
      description = ''
        The directory in which to look for host ${system} configurations.
      '';
    };

    specialArgs = mkOption {
      default = cfg.globalArgs;
      defaultText = literalExpression "ezConfigs.globalArgs";
      type = types.attrsOf types.anything;
      description = ''
        Extra arguments to pass to all ${system} configurations.
      '';
    };

    hosts = mkOption {
      default = { };
      type = types.attrsOf (types.submodule hostOptions);
      example = literalExpression ''
        {
          hostA.arch = "x86_64";
          hostB.arch = "aarch64";
        }
      '';
      description = ''
        An attribute set of ${system} host definitions to create configurations for.
      '';
    };
  };

in
{
  options.ezConfigs = {
    root = mkOption {
      type = types.pathInStore;
      example = literalExpression "./.";
      description = ''
        The root from which configuration modules should be searched.
      '';
    };

    globalArgs = mkOption {
      default = { };
      example = literalExpression "{ inherit inputs; }";
      type = types.attrsOf types.anything;
      description = ''
        Extra arguments to pass to all systems.
      '';
    };

    hm = {
      modulesDirectory = mkOption {
        default = "${cfg.root}/home";
        defaultText = "\${ezConfigs.root}/home";
        type = types.pathInStore;
        description = ''
          The directory in which to look for home-manager configurations.
        '';
      };

      usersDirectory = mkOption {
        default = "${cfg.root}/users";
        defaultText = literalExpression "\"\${ezConfigs.root}/users\"";
        type = types.pathInStore;
        description = ''
          The directory in which to look for user specific home-manager configurations.
        '';
      };

      extraSpecialArgs = mkOption {
        default = cfg.globalArgs;
        defaultText = literalExpression "ezConfigs.globalArgs";
        type = types.attrsOf types.anything;
        description = ''
          Extra arguments to pass to all home-manager configurations.
        '';
      };

      users = mkOption {
        default = [ ];
        type = types.attrsOf (types.submodule userOptions);

        example = literalExpression ''
          {
            alice = { };
            bob = { };
          }
        '';

        description = ''
          A list of user definitions to create home manager configurations for.
        '';
      };
    };

    nixos = hostsOptions "nixos";

    darwin = hostsOptions "darwin";
  };

  config.flake = {
    homeConfigurations = userConfigs
      {
        inherit (cfg.hm)
          modulesDirectory
          usersDirectory
          extraSpecialArgs;
      }
      cfg.hm.users;

    nixosConfigurations = systemsWith
      {
        systemBuilder = nixosSystem;
        systemSuffix = "linux";
        inherit (cfg.nixos)
          modulesDirectory
          hostsDirectory
          specialArgs;
      }
      cfg.nixos.hosts;

    darwinConfigurations = systemsWith
      {
        systemBuilder = darwinSystem;
        systemSuffix = "darwin";
        inherit (cfg.darwin)
          modulesDirectory
          hostsDirectory
          specialArgs;
      }
      cfg.darwin.hosts;
  };
}
