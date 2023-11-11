{ darwin, home-manager, nixpkgs, ... }: { lib, config, ... }:
let

  inherit (builtins) pathExists readDir readFileType;
  inherit (nixpkgs.lib) mkOption types nixosSystem optionals literalExpression mapAttrs concatMapAttrs;
  inherit (nixpkgs.lib.strings) hasSuffix removeSuffix;
  inherit (darwin.lib) darwinSystem;
  inherit (home-manager.lib) homeManagerConfiguration;
  cfg = config.ezConfigs;

  # Creates an attrset of nixosConfigurations or darwinConfigurations.
  systemsWith = { systemBuilder, systemSuffix, ezModules, hostModules, specialArgs }: hosts:
    mapAttrs
      (name: { arch, importDefault }: systemBuilder {
        specialArgs = specialArgs // { inherit ezModules; };
        system = "${arch}-${systemSuffix}";
        modules = [ (hostModules.${name} or { }) ]
          ++ optionals importDefault [ (ezModules.default or { }) ];
      })
      hosts;

  allHosts =
    (config.flake.nixosConfigurations //
      config.flake.darwinConfigurations);

  # Creates an attrset of home manager confgurations for each user on each host.
  userConfigs = { ezModules, userModules, extraSpecialArgs }: users:
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
                inherit pkgs;
                extraSpecialArgs = extraSpecialArgs // { inherit ezModules; };
                modules = [ (userModules.${user} or { }) ] ++ # user module
                  optionals importDefault ([ (ezModules.default or { }) ] ++ # default module
                    optionals isDarwin [ (ezModules.darwin or { }) ] ++ # default darwin module
                    optionals isLinux [ (ezModules.linux or { }) ]); # default linux module
              };
            })
          allHosts)
      users;

  readModules = dir:
    if pathExists "${dir}.nix" && readFileType "${dir}.nix" == "regular" then
      { default = dir; }
    else if pathExists dir && readFileType dir == "directory" then
      concatMapAttrs
        (entry: type:
          let
            dirDefault = "${dir}/${entry}/default.nix";
          in
          if type == "regular" && hasSuffix ".nix" entry then
            { ${removeSuffix ".nix" entry} = "${dir}/${entry}"; }
          else if pathExists dirDefault && readFileType dirDefault == "regular" then
            { ${entry} = dirDefault; }
          else { }
        )
        (readDir dir)
    else { }
  ;

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

  config.flake = rec {
    homeModules = readModules cfg.hm.modulesDirectory;
    nixosModules = readModules cfg.nixos.modulesDirectory;
    darwinModules = readModules cfg.darwin.modulesDirectory;

    homeConfigurations = userConfigs
      {
        userModules = readModules cfg.hm.usersDirectory;
        ezModules = homeModules;
        inherit (cfg.hm) extraSpecialArgs;
      }
      cfg.hm.users;

    nixosConfigurations = systemsWith
      {
        systemBuilder = nixosSystem;
        systemSuffix = "linux";
        hostModules = readModules cfg.nixos.hostsDirectory;
        ezModules = nixosModules;
        inherit (cfg.nixos)
          specialArgs;
      }
      cfg.nixos.hosts;

    darwinConfigurations = systemsWith
      {
        systemBuilder = darwinSystem;
        systemSuffix = "darwin";
        hostModules = readModules cfg.darwin.hostsDirectory;
        ezModules = darwinModules;
        inherit (cfg.darwin) specialArgs;
      }
      cfg.darwin.hosts;
  };
}
