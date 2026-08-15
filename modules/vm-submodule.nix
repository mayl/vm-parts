# The `vms.<name>` submodule.
{
  inputs,
  flakeConfig,
  registryLib,
  extras,
  formatOptionsModule,
}:
{
  name,
  config,
  lib,
  ...
}:
let
  inherit (lib) mkOption types;

  # The machine we build when `nixos` is not assigned directly.
  defaultNixos = config.nixpkgs.lib.nixosSystem {
    inherit (config) specialArgs;
    modules =
      config.modules
      ++ lib.optional (config.system != null) {
        _file = "${toString ./vm-submodule.nix} (vms.${name}.system)";
        nixpkgs.hostPlatform = lib.mkDefault config.system;
      };
  };

  # Evaluate one format by extending the base machine, so that a machine with six
  # formats evaluates its common configuration once rather than six times.
  mkFormatOutput =
    format:
    let
      formatModule = registryLib.resolve {
        inherit name format;
        registry = config.formatModules;
        aliases = flakeConfig.formatAliases;
      };

      evaluated = config.nixos.extendModules {
        modules = [
          formatOptionsModule
          formatModule
        ];
      };

      cfg = evaluated.config;

      # `lib.evalModules` strips `_module` out of `.config`, so it is reached on
      # the result itself. `extendModules` returns a bare evalModules result, so
      # the top-level `.pkgs` that nixos/lib/eval-config.nix bolts on is not
      # guaranteed to be present -- go through `_module.args` instead.
      pkgs = evaluated._module.args.pkgs;

      drv =
        cfg.system.build.${cfg.format.attr} or (throw ''
          vm-parts: vms.${name}.${format} builds `system.build.${cfg.format.attr}',
          but that attribute is not defined by the format module.

          Set `format.attr` to whichever `system.build` attribute this format
          actually produces.
        '');

      file = pkgs.buildPackages.runCommandLocal "${drv.name}-file" { } ''
        if [ ! -e "${drv}/${cfg.format.filePath}" ]; then
          echo "vm-parts: vms.${name}.${format}: expected the artifact" >&2
          echo "  ${cfg.format.filePath}" >&2
          echo "inside ${drv}, but it is not there. Contents:" >&2
          ls -la "${drv}" >&2 || true
          exit 1
        fi
        ln -s "${drv}/${cfg.format.filePath}" "$out"
      '';
    in
    # `//` rather than `overrideAttrs`: nixos-generators used `overrideAttrs` to
    # attach `passthru.config`, which changes the store path and is not safe on
    # every `system.build.*` derivation (not all of them come from
    # `stdenv.mkDerivation`). `//` leaves drvPath/outPath untouched and is exactly
    # how passthru already behaves.
    drv
    // {
      config = cfg;
      nixos = evaluated;
    }
    // lib.optionalAttrs (cfg.format.filePath != null) { inherit file; };
in
{
  _file = ./vm-submodule.nix;

  options = {
    nixos = mkOption {
      type = types.raw;
      default = defaultNixos;
      defaultText = lib.literalMD ''
        a `nixosSystem` built from {option}`modules`, {option}`system` and
        {option}`specialArgs`
      '';
      description = ''
        The evaluated NixOS system for this machine.

        Leave it alone to have one built from {option}`modules`, or assign an
        already-evaluated configuration to adopt it:

        ```nix
        vms.myMachine.nixos = config.flake.nixosConfigurations.myMachine;
        ```

        Formats are produced by calling `extendModules` on this value, so both
        routes behave identically from here on.
      '';
    };

    nixpkgs = mkOption {
      type = types.raw;
      default =
        inputs.nixpkgs or (throw ''
          vm-parts: vms.${name} needs a nixpkgs to evaluate against, but the flake
          has no `nixpkgs` input.

          Add one, or set `vms.${name}.nixpkgs` explicitly.
        '');
      defaultText = lib.literalExpression "inputs.nixpkgs";
      description = ''
        The nixpkgs flake used to build the default {option}`nixos`. Unused when
        {option}`nixos` is assigned directly.
      '';
    };

    system = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "x86_64-linux";
      description = ''
        Convenience for setting `nixpkgs.hostPlatform` on the built machine. When
        non-null a module defining it (at `mkDefault` priority) is appended to
        {option}`modules`. Setting `nixpkgs.hostPlatform` in your own modules
        instead is equally fine.
      '';
    };

    modules = mkOption {
      type = types.listOf types.raw;
      default = [ ];
      description = "NixOS modules passed to `nixosSystem` when building the default {option}`nixos`.";
    };

    specialArgs = mkOption {
      type = types.attrsOf types.raw;
      default = { };
      example = lib.literalExpression "{ inherit inputs; }";
      description = ''
        `specialArgs` passed to `nixosSystem`. Nothing is injected implicitly --
        if your modules expect an `inputs` argument, pass it here.
      '';
    };

    formats = mkOption {
      type = types.listOf types.str;
      example = [
        "vm"
        "vbox"
        "iso"
      ];
      description = ''
        Exactly the formats exposed as flake outputs for this machine. Each one
        becomes `<outputName>.<format>`, buildable with
        `nix build .#<outputName>.<format>`.

        Names are looked up in {option}`formatModules`, falling back to
        {option}`formatAliases`. There is no default: listing them is how you
        keep a machine from carrying build targets you never asked for.
      '';
    };

    formatModules = mkOption {
      type = types.attrsOf types.deferredModule;
      default = { };
      example = lib.literalExpression ''
        {
          # customise a built-in -- this MERGES into it, it does not replace it
          virtualbox.image.baseName = "my-appliance";

          # define a new one
          my-format = { modulesPath, ... }: {
            imports = [ "''${modulesPath}/installer/cd-dvd/installation-cd-base.nix" ];
            format.attr = "image";
          };
        }
      '';
      description = ''
        Format registry for this machine.

        Pre-populated with every `image.modules` variant of {option}`nixos` plus
        the run-script formats nixpkgs lacks. Your definitions are merged in by
        the module system, so defining a name that already exists *customises*
        it rather than replacing it; use `lib.mkForce` for the latter.
      '';
    };

    outputName = mkOption {
      type = types.str;
      default = name;
      description = "Top-level flake output attribute this machine's formats appear under.";
    };

    exportNixosConfiguration = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Whether to also expose {option}`nixos` as
        `nixosConfigurations.<outputName>`, for `nixos-rebuild`.

        Off by default, because the machine described by {option}`modules` is
        usually *format-agnostic*: bootloader, filesystems and partitioning come
        from the format, which is the entire point of describing a machine once
        and building it many ways. Such a configuration has no valid
        `system.build.toplevel` on its own, so exporting it would produce a
        `nixosConfigurations` entry that fails `nix flake check`.

        Turn it on for machines that are also complete systems in their own
        right. Do not turn it on for a machine whose {option}`nixos` was adopted
        from `flake.nixosConfigurations` -- that would define the same output
        attribute twice.
      '';
    };

    outputs = mkOption {
      type = types.lazyAttrsOf types.raw;
      readOnly = true;
      internal = true;
      description = "Computed format outputs for this machine.";
    };
  };

  config = {
    # Layered registry. These merge rather than override: a definition of
    # `virtualbox` here and one from the user both apply, which is what makes
    # "customise a built-in" work. Order is therefore not precedence.
    formatModules = lib.mkMerge [
      (registryLib.imageFormats {
        inherit name;
        inherit (config) nixos;
      })
      extras
      flakeConfig.formatModules
    ];

    # `genAttrs` over the requested names only: formats that were not asked for
    # are never evaluated. See the laziness contract in the README.
    outputs = lib.genAttrs config.formats mkFormatOutput;
  };
}
