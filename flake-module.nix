{ inputs, lib, config, ... }:
let

  inherit (builtins) pathExists readDir readFileType elemAt isList;
  inherit (lib) mkOption types optionals literalExpression mapAttrs concatMapAttrs genAttrs id;
  inherit (lib.strings) hasSuffix removeSuffix;
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
    { os
    , ezModules
    , hostModules
    , specialArgs
    , defaultHost
    , extraSpecialArgs
    , userModules
    , ezHomeModules
    , users
    }: hosts:
    mapAttrs
      (name: configModule:
      let
        hostSettings = hosts.${name} or defaultHost;
        inherit (hostSettings) importDefault;
        # Convert a list of strings into an attribute set with identical names and values.
        userHomeModules =
          if isList hostSettings.userHomeModules
          then genAttrs hostSettings.userHomeModules id
          else hostSettings.userHomeModules;
        hmModule =
          if inputs ? home-manager then
            (
              if os == "linux"
              then inputs.home-manager.nixosModules.default
              else inputs.home-manager.darwinModules.default
            )
          else
            throw ''
              home-manager input not found, but host ${name} was configured with `userHomeModules`.
              Please add a home-manager input to your flake.
            '';
        systemBuilder =
          if os == "linux" then
            (
              if inputs ? nixpkgs
              then inputs.nixpkgs.lib.nixosSystem
              else
                throw ''
                  nixpkgs input not found, but host ${name} present in nixosConfigurations directory.
                  Please add a nixpkgs input to your flake.
                ''
            )
          else
            (if inputs ? darwin
            then inputs.darwin.lib.darwinSystem
            else if inputs ? nix-darwin
            then inputs.nix-darwin.lib.darwinSystem
            else
              throw ''
                darwin or nix-darwin input not found, but host ${name} present in darwinConfigurations directory.
                Please add a darwin or nix-darwin input to your flake.
              ''
            );
      in
      systemBuilder {
        specialArgs = specialArgs // { inherit ezModules; };
        modules = [
          configModule
          { networking.hostName = lib.mkDefault "${name}"; }
        ] ++ optionals importDefault [ (ezModules.default or { }) ]
        ++ optionals (userHomeModules != { }) [
          hmModule
          ({ pkgs, ... }: {
            home-manager = {
              extraSpecialArgs = extraSpecialArgs // { ezModules = ezHomeModules; };
              users = mapAttrs
                (_: user:
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
                    throw ''User ${user} not found inside homeConfigurations directory, but was added to ${name}.userHomeModules''
                )
                userHomeModules;
            };
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
          homeManagerConfiguration =
            if inputs ? home-manager
            then inputs.home-manager.lib.homeManagerConfiguration
            else
              throw ''
                home-manager input not found, but user ${user} present in homeConfigurations directory.
                Please add a home-manager input to your flake.
              '';
        in
        if standalone.enable
        then
          {
            ${user} = homeManagerConfiguration {
              inherit (standalone) pkgs;
              extraSpecialArgs = extraSpecialArgs //
                { inherit ezModules; } //
                # We still want to pass in osConfig even when there is none,
                # so that modules evaluate properly when using that argument
                (if passInOsConfig then { osConfig = { }; } else { });
              modules = modules standalone.pkgs.stdenv;
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

  readModules = { dir, entryPoint ? "default.nix" }:
    if pathExists "${dir}.nix" && readFileType "${dir}.nix" == "regular" then
      { default = dir; }
    else if pathExists dir && readFileType dir == "directory" then
      concatMapAttrs
        (entry: type:
          let
            dirDefault = "${dir}/${entry}/${entryPoint}";
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

  injectEarly = earlyArgs: modules:
    if earlyArgs == { }
    then modules
    else
      mapAttrs
        (_: path:
          let
            mod = import path;
          in
          if lib.isFunction mod
          then
            let
              modArgs = lib.functionArgs mod;
              subArgs = lib.filterAttrs (name: _: builtins.hasAttr name modArgs) earlyArgs;
              left = builtins.removeAttrs modArgs (builtins.attrNames subArgs);
              func = args: mod (args // subArgs);
            in
            lib.setFunctionArgs func left
          else path
        )
        modules;

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
      importDefault = mkOption {
        default = true;
        type = types.bool;
        description = ''
          Whether to import the default module for this host.
        '';
      };

      userHomeModules = mkOption {
        default = [ ];
        type = types.either (types.listOf types.str) (types.attrsOf types.str);
        example = literalExpression ''
          { 
            alice = "alice-minimal";
            bob = "bob-full";
          }
        '';
        description = ''
          List or attribute set of users in ''${ezConfigs.hm.usersDirectory},
          whose comfigurations to import as home manager ${system}Modules.
          If it's a list, each user is assumed to have the same name as the homeModule.
          You can override this by using an attribute set, where the attribute name
          is the name of the host user, while value is the name of the homeModule.
          They will be put inside `home-manager.''${user}.imports` list for this host.

          When this option is set, the `home-manager.extraSpecialArgs` option
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
        This will be the nixosConfiguration.config or darwinConfiguration.config,
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

      pkgs = mkOption {
        type = types.pkgs;
        example = literalExpression "import nixpkgs {system = \"x86_64-linux\"}";
        description = ''
          The package set with which to construct the homeManagerConfiguration.

          Non standalone user configurations will use the package set of the host system.
        '';
      };
    };
  };


  configurationOptions = configType: {
    modulesDirectory = mkOption {
      default = if cfg.root != null then "${cfg.root}/${configType}-modules" else ./unset-directory;
      defaultText = literalExpression "\"\${ezConfigs.root}/${configType}-modules\"";
      type = types.path;
      description = ''
        The directory containing ${configType}Modules.
      '';
    };

    configurationsDirectory = mkOption {
      default = if cfg.root != null then "${cfg.root}/${configType}-configurations" else ./unset-directory;
      defaultText = literalExpression "\"\${ezConfigs.root}/${configType}-configurations\"";
      type = types.path;
      description = ''
        The directory containing ${configType}Configurations.
      '';
    };

    configurationEntryPoint = mkOption {
      default = "default.nix";
      defaultText = literalExpression "\"default.nix\"";
      type = types.str;
      description = ''
        Entry point file for ${configType}Configurations.
      '';
    };

    earlyModuleArgs = mkOption {
      default = cfg.earlyModuleArgs;
      defaultText = literalExpression "ezConfigs.earlyModuleArgs";
      type = types.attrsOf types.anything;
      description = ''
        Extra arguments to pass to all ${configType}Modules before exporting them.
      '';
    };

  } // (
    if configType == "home" then
      {
        extraSpecialArgs = mkOption {
          default = cfg.globalArgs;
          defaultText = literalExpression "ezConfigs.globalArgs";
          type = types.attrsOf types.anything;
          description = ''
            Extra arguments to pass to all homeConfigurations.
          '';
        };

        users = mkOption {
          default = { };
          type = types.attrsOf (types.submodule userOptions);

          example = literalExpression ''
            {
              alice = {
                standalone = {
                  enable = true;
                  pkgs = import nixpkgs { system = "x86_64-linux"; };
                };
              };

              bob = {
                importDefault = false;
              };
            }
          '';

          description = ''
            Settings for creating homeConfigurations.

            It's not neccessary to specify this option to create flake outputs.
            It's only needed if you want to change the defaults for specific homeConfigurations.
          '';
        };
      }
    else
      {
        specialArgs = mkOption {
          default = cfg.globalArgs;
          defaultText = literalExpression "ezConfigs.globalArgs";
          type = types.attrsOf types.anything;
          description = ''
            Extra arguments to pass to all ${configType}Configurations.
          '';
        };

        hosts = mkOption {
          default = { };
          type = types.attrsOf (types.submodule (hostOptions configType));
          example = literalExpression ''
            {
              hostA = {
                userHomeModules = [ "bob" ];
              };

              hostB = {
                importDefault = false;
                arch = "aarch64
              };
            }
          '';
          description = ''
            Settings for creating ${configType}Configurations.

            It's not neccessary to specify this option to create flake outputs.
            It's only needed if you want to change the defaults for specific ${configType}Configurations.
          '';
        };
      }
  );

in
{
  options.ezConfigs = {
    root = mkOption {
      default = null;
      type = types.nullOr types.path;
      example = literalExpression "./.";
      description = ''
        The root from which configurations and modules should be searched.
      '';
    };

    globalArgs = mkOption {
      default = { };
      example = literalExpression "{ inherit inputs; }";
      type = types.attrsOf types.anything;
      description = ''
        Extra arguments to pass to all configurations.
      '';
    };

    earlyModuleArgs = mkOption {
      default = { };
      example = literalExpression "{ inherit inputs; }";
      type = types.attrsOf types.anything;
      description = ''
        Extra arguments to pass to all modules before exporting them.
      '';
    };

    home = configurationOptions "home";

    nixos = configurationOptions "nixos";

    darwin = configurationOptions "darwin";
  };

  config.flake = rec {
    homeModules = injectEarly cfg.home.earlyModuleArgs (readModules { dir = cfg.home.modulesDirectory; });
    nixosModules = injectEarly cfg.nixos.earlyModuleArgs (readModules { dir = cfg.nixos.modulesDirectory; });
    darwinModules = injectEarly cfg.darwin.earlyModuleArgs (readModules { dir = cfg.darwin.modulesDirectory; });

    homeConfigurations = userConfigs
      {
        userModules = readModules { dir=cfg.home.configurationsDirectory; entryPoint=cfg.home.configurationEntryPoint; };
        defaultUser = defaultSubmodule userOptions;
        ezModules = homeModules;
        inherit (cfg.home) extraSpecialArgs;
      }
      cfg.home.users;

    nixosConfigurations = systemsWith
      {
        os = "linux";
        hostModules = readModules { dir=cfg.nixos.configurationsDirectory; entryPoint=cfg.nixos.configurationEntryPoint; };
        defaultHost = defaultSubmoduleAttr ((configurationOptions "nixos").hosts.type);
        ezModules = nixosModules;
        userModules = readModules { dir=cfg.home.configurationsDirectory; entryPoint=cfg.home.configurationEntryPoint; };
        ezHomeModules = homeModules;
        inherit (cfg.nixos) specialArgs;
        inherit (cfg.home) extraSpecialArgs users;
      }
      cfg.nixos.hosts;

    darwinConfigurations = systemsWith
      {
        os = "darwin";
        hostModules = readModules { dir=cfg.darwin.configurationsDirectory; entryPoint=cfg.darwin.configurationEntryPoint; };
        defaultHost = defaultSubmoduleAttr ((configurationOptions "darwin").hosts.type);
        ezModules = darwinModules;
        userModules = readModules { dir=cfg.home.configurationsDirectory; entryPoint=cfg.home.configurationEntryPoint; };
        ezHomeModules = homeModules;
        inherit (cfg.darwin) specialArgs;
        inherit (cfg.home) extraSpecialArgs users;
      }
      cfg.darwin.hosts;
  };
}
