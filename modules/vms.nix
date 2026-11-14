# The flake-parts module: `vms.<name>` in, top-level flake outputs out.
{
  config,
  options,
  lib,
  inputs,
  ...
}:
let
  registryLib = import ./registry.nix { inherit lib; };
  extras = import ../extras;
  defaultAliases = import ./aliases.nix;
  formatOptionsModule = ./format-options.nix;

  vmModule = import ./vm-submodule.nix {
    inherit
      inputs
      registryLib
      extras
      formatOptionsModule
      ;
    flakeConfig = config;
  };

  # Output names a machine must not take. Two sources:
  #
  # - Every output the flake-parts evaluation itself declares an option for
  #   (`packages`, `checks`, ... plus whatever the consumer's other flake modules
  #   add, e.g. `flakeModules` or `homeConfigurations`). Read off the option
  #   declarations, which never depend on `config`, so this cannot recurse.
  # - Standard or conventional outputs that may not be declared as options here:
  #   legacy singular forms, other ecosystems' outputs, and the attributes Nix
  #   itself puts on a flake.
  declaredOutputs = lib.filter (n: !lib.hasPrefix "_" n) (
    lib.attrNames (options.flake.type.getSubOptions [ ])
  );
  reservedNames = declaredOutputs ++ [
    "apps"
    "bundlers"
    "checks"
    "darwinConfigurations"
    "darwinModules"
    "defaultApp"
    "defaultPackage"
    "defaultTemplate"
    "devShell"
    "devShells"
    "flakeModule"
    "flakeModules"
    "formatModules"
    "formatter"
    "herculesCI"
    "homeConfigurations"
    "homeModules"
    "hydraJobs"
    "legacyPackages"
    "lib"
    "modules"
    "nixosConfigurations"
    "nixosModule"
    "nixosModules"
    "overlay"
    "overlays"
    "packages"
    "templates"
    # Attributes Nix sets on the flake itself.
    "_type"
    "inputs"
    "outPath"
    "outputs"
    "self"
    "sourceInfo"
  ];

  # The output name of `vms.${n}`, refusing names that would shadow a standard
  # output or another machine. Both mistakes would otherwise be silent: the
  # outputs are built with `listToAttrs`, which keeps one of two equal names and
  # drops the other without a word.
  #
  # LAZINESS: reads only `outputName`s, never formats.
  checkedOutputName =
    n: vm:
    let
      sharers = lib.attrNames (lib.filterAttrs (_: other: other.outputName == vm.outputName) config.vms);
    in
    if lib.elem vm.outputName reservedNames then
      throw ''
        vm-parts: vms.${n} would be exposed as the top-level flake output
        `${vm.outputName}', which collides with a standard flake output.

        Set `vms.${n}.outputName` to something else.
      ''
    else if lib.length sharers > 1 then
      throw ''
        vm-parts: vms.${lib.concatStringsSep " and vms." sharers} all have the output
        name `${vm.outputName}', so only one of them could be exposed.

        Give each a distinct `outputName`.
      ''
    else
      vm.outputName;
in
{
  _file = ./vms.nix;
  _class = "flake";

  options = {
    vms = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submoduleWith { modules = [ vmModule ]; });
      default = { };
      example = lib.literalExpression ''
        {
          myMachine = {
            system = "x86_64-linux";
            modules = [ ./machine.nix ];
            formats = [ "vm" "vbox" "iso" ];
          };
        }
      '';
      description = ''
        NixOS machines to expose as buildable, multi-format flake outputs.

        Each machine `m` with format `f` becomes the top-level output `m.f`, so
        `nix build .#m.f` works directly. Formats whose artifact is a single file
        additionally carry `m.f.file`, a symlink to that file.
      '';
    };

    formatModules = lib.mkOption {
      type = lib.types.attrsOf lib.types.deferredModule;
      default = { };
      description = ''
        Format modules made available to every machine in {option}`vms`, on top
        of the ones discovered from each machine's own `image.modules`.

        Definitions merge into same-named built-ins rather than replacing them.
        For a single machine, use {option}`vms.<name>.formatModules` instead.

        Also re-exported as the `formatModules` flake output, so other flakes can
        consume formats defined here.
      '';
    };

    formatAliases = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = ''
        Alternative names for formats, resolved when a requested name is not in
        the registry. Pre-populated with the nixos-generators names that were
        renamed on the way into nixpkgs (`vbox`, `qcow`, `gce`, ...).

        A name present in the registry always wins over an alias.
      '';
    };
  };

  config = {
    formatAliases = lib.mapAttrs (_: lib.mkDefault) defaultAliases;

    # Opt-in mirror of the format outputs into `packages`, for `nix flake show`.
    #
    # LAZINESS: iterates over machines, then over each machine's `outputs`, whose
    # names are exactly its `formats`. The registry is never touched, and the
    # machine's own platform is only read for machines that opted in.
    perSystem =
      { system, ... }:
      {
        packages = lib.mkMerge (
          lib.mapAttrsToList (
            n: vm:
            lib.optionalAttrs (vm.exposeAsPackages && vm.nixos.config.nixpkgs.hostPlatform.system == system) (
              let
                outputName = checkedOutputName n vm;
              in
              lib.mapAttrs' (format: drv: lib.nameValuePair "${outputName}-${format}" drv) vm.outputs
            )
          ) config.vms
        );
      };

    flake = lib.mkMerge [
      (lib.mapAttrs' (n: vm: lib.nameValuePair (checkedOutputName n vm) vm.outputs) config.vms)

      {
        # Keyed by `outputName`, as documented, not by the `vms` attribute name.
        nixosConfigurations = lib.mapAttrs' (n: vm: lib.nameValuePair (checkedOutputName n vm) vm.nixos) (
          lib.filterAttrs (_: vm: vm.exportNixosConfiguration) config.vms
        );
      }

      # Only what was defined here, deliberately not the `image.modules`-derived
      # entries: those belong to the consumer's own nixpkgs, and re-exporting them
      # would hand downstream flakes formats pinned to ours.
      #
      # Emitted only when non-empty: `formatModules` is not a standard flake
      # output, so an unconditional definition would make every consumer that
      # defines no custom formats eat an "unknown flake output" warning.
      # (`attrNames` keeps this to names, never values -- see the laziness note.)
      (lib.optionalAttrs (lib.attrNames config.formatModules != [ ]) {
        formatModules = config.formatModules;
      })
    ];
  };
}
