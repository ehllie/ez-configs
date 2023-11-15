{ darwin, home-manager, nixpkgs, ... }: { lib, config, ... }:
let

  inherit (builtins) pathExists readDir readFileType elemAt;
  inherit (nixpkgs.lib) mkOption types nixosSystem optionals literalExpression mapAttrs concatMapAttrs genAttrs;
  inherit (nixpkgs.lib.strings) hasSuffix removeSuffix;
  inherit (darwin.lib) darwinSystem;
  inherit (home-manager.lib) homeManagerConfiguration;
  cfg = config.ezConfigs;



  # Creates a list of imports to include for a given user.
  # This is used in both systemsWith and userConfigs,
  # so it's convinient to have it exported as a top level function
  userImports = { stdenv, userModules, ezModules, user, importDefault }:
    [ (userModules.${user} or { }) ] ++ # user module
    optionals importDefault ([ (ezModules.default or { }) ] ++ # default module
    optionals stdenv.isDarwin [ (ezModules.darwin or { }) ] ++ # default darwin module
    optionals stdenv.isLinux [ (ezModules.linux or { }) ]); # default linux module;

  # Creates an attrset of nixosConfigurations or darwinConfigurations.
  systemsWith =
    { systemBuilder
    , systemSuffix
    , ezModules
    , hostModules
    , specialArgs
    , defaultHost
    , hmModule
    , extraSpecialArgs
    , userModules
    , ezHomeModules
    , users
    }: hosts:
    mapAttrs
      (name: configModule:
      let
        hostSettings = hosts.${name} or defaultHost;
        inherit (hostSettings) arch importDefault userHomeModules;
      in
      systemBuilder {
        specialArgs = specialArgs // { inherit ezModules; };
        system = "${arch}-${systemSuffix}";
        modules = [ configModule ]
          ++ optionals importDefault [ (ezModules.default or { }) ]
          ++ optionals (userHomeModules != [ ]) [
          hmModule
          { home-manager.extraSpecialArgs = extraSpecialArgs // { ezModules = ezHomeModules; }; }
          ({ pkgs, ... }: {
            home-manager.users = genAttrs
              userHomeModules
              (user:
                if userModules ? ${user} then
                  let
                    userSettings = users.${user} or (defaultSubmodule userOptions);
                  in
                  {
                    imports = userImports {
                      inherit (pkgs) stdenv;
                      inherit (userSettings) importDefault;
                      inherit user userModules;
                      ezModules = ezHomeModules;
                    };
                  }
                else
                  throw "User ${user} not found inside ${cfg.hm.usersDirectory}"
              );
          })
        ];
      })
      hostModules;

  allHosts =
    (config.flake.nixosConfigurations //
      config.flake.darwinConfigurations);

  # Creates an attrset of home manager confgurations for each user on each host.
  userConfigs = { ezModules, userModules, extraSpecialArgs, defaultUser }: users:
    concatMapAttrs
      (user: configModule:
        let
          userSettings = users.${user} or defaultUser;
          inherit (userSettings)
            nameFunction
            importDefault
            passInOsConfig;
          standalone = userSettings.standalone or { enable = false; };
          mkName =
            if nameFunction == null
            then host: "${user}@${host}"
            else nameFunction;
          modules = stdenv: userImports { inherit stdenv importDefault user ezModules userModules; };
        in
        if standalone.enable
        then
          let
            pkgs = import nixpkgs { inherit (standalone) system; };
          in
          {
            ${user} = homeManagerConfiguration {
              inherit pkgs;
              extraSpecialArgs = extraSpecialArgs //
                { inherit ezModules; } //
                # We still want to pass in osConfig even when there is none,
                # so that modules evaluate properly when using that argument
                (if passInOsConfig then { osConfig = { }; } else { });
              modules = modules pkgs.stdenv;
            };
          }
        else
          concatMapAttrs
            (host: { config, pkgs, ... }: {
              ${mkName host} = homeManagerConfiguration {
                inherit pkgs;
                extraSpecialArgs = extraSpecialArgs //
                  { inherit ezModules; } //
                  (if passInOsConfig then { osConfig = config; } else { });
                modules = modules pkgs.stdenv;
              };
            })
            allHosts
      )
      userModules;

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

  # This is a workaround the types.attrsOf (type.submodule ...) functionality.
  # We can't ensure that each host/ user present in the appropriate directory
  # is also present in the attrset, so we need to create a default module for it.
  # That way we can fallback to it if it's not present in the attrset.
  # Is there a better way to do this? Maybe defining a custom type?
  defaultSubmodule = submodule:
    concatMapAttrs
      (opt: optDef:
        if optDef ? default then
          { ${opt} = optDef.default; }
        else { }
      )
      submodule.options;

  # Getting the first submodule seems to work, but not sure if it's the best way.
  defaultSubmoduleAttr = attrsType:
    defaultSubmodule (elemAt attrsType.getSubModules 0);

  hostOptions = system: {
    options = {
      arch = mkOption {
        type = types.enum [ "x86_64" "aarch64" ];
        default = if system == "darwin" then "aarch64" else "x86_64";
        description = "The architecture of the system.";
      };

      importDefault = mkOption {
        default = true;
        type = types.bool;
        description = ''
          Whether to import the default module for this host.
        '';
      };

      userHomeModules = mkOption {
        default = [ ];
        type = types.listOf types.str;
        description = ''
          List of users in ''${ezConfigs.hm.usersDirectory},
          whose comfigurations to import as home manager ${system} modules.

          When this list is not empty, the `home-manager.extraSpecialArgs` option
          is also set to the one it would recieve in homeManagerConfigurations
          output, and the appropriate homeManager module is imported.
        '';

      };
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

    passInOsConfig = mkOption {
      default = true;
      type = types.bool;
      description = ''
        Whether to pass the osConfig argument to extraSpecialArgs.
        This will be the nixosConfiguration or darwinConfiguration,
        whose pkgs are being used to build this homeConfiguration.
      '';
    };

    standalone = {
      enable = mkOption {
        default = false;
        type = types.bool;
        description = ''
          Whether to create a standalone user configuration.

          By default each user and host pair gets its own homeConfigurations attribute,
          and the pkgs passed into homeConfiguration function come from that system.

          This will prevent the ''${user}@''${host} outputs from being created.
          Instead a standalone user configuration will be created with user name.
        '';
      };

      system = mkOption {
        type = types.str;
        description = ''
          The system with which to create the pkgs set for the configuration.

          homeManagerConfiguration function requires a `pkgs` argument,
          and this is the system that will be passed to the `import nixpkgs { inherit system; }`
          call.
        '';
      };
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
      default = "${cfg.root}/${system}-hosts";
      defaultText = literalExpression "\"\${ezConfigs.root}/${system}-hosts\"";
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
      type = types.attrsOf (types.submodule (hostOptions system));
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
        default = { };
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
        defaultUser = defaultSubmodule userOptions;
        ezModules = homeModules;
        inherit (cfg.hm) extraSpecialArgs;
      }
      cfg.hm.users;

    nixosConfigurations = systemsWith
      {
        systemBuilder = nixosSystem;
        systemSuffix = "linux";
        hostModules = readModules cfg.nixos.hostsDirectory;
        defaultHost = defaultSubmoduleAttr ((hostsOptions "nixos").hosts.type);
        ezModules = nixosModules;
        hmModule = home-manager.nixosModules.default;
        userModules = readModules cfg.hm.usersDirectory;
        ezHomeModules = homeModules;
        inherit (cfg.nixos) specialArgs;
        inherit (cfg.hm) extraSpecialArgs users;
      }
      cfg.nixos.hosts;

    darwinConfigurations = systemsWith
      {
        systemBuilder = darwinSystem;
        systemSuffix = "darwin";
        hostModules = readModules cfg.darwin.hostsDirectory;
        defaultHost = defaultSubmoduleAttr ((hostsOptions "darwin").hosts.type);
        ezModules = darwinModules;
        hmModule = home-manager.darwinModules.default;
        userModules = readModules cfg.hm.usersDirectory;
        ezHomeModules = homeModules;
        inherit (cfg.darwin) specialArgs;
        inherit (cfg.hm) extraSpecialArgs users;
      }
      cfg.darwin.hosts;
  };
}
