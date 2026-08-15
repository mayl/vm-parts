# The flake-parts module: `vms.<name>` in, top-level flake outputs out.
{
  config,
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

  # Standard flake output attributes. A machine landing on one of these would
  # silently shadow or collide with a real output, so refuse up front.
  reservedNames = [
    "apps"
    "checks"
    "darwinConfigurations"
    "devShells"
    "formatter"
    "flakeModules"
    "homeConfigurations"
    "hydraJobs"
    "legacyPackages"
    "lib"
    "modules"
    "nixosConfigurations"
    "nixosModules"
    "overlays"
    "packages"
    "templates"
    "formatModules"
  ];

  checkedOutputName =
    n: vm:
    if lib.elem vm.outputName reservedNames then
      throw ''
        vm-parts: vms.${n} would be exposed as the top-level flake output
        `${vm.outputName}', which collides with a standard flake output.

        Set `vms.${n}.outputName` to something else.
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

    flake = lib.mkMerge [
      (lib.mapAttrs' (n: vm: lib.nameValuePair (checkedOutputName n vm) vm.outputs) config.vms)

      {
        nixosConfigurations = lib.mapAttrs (_: vm: vm.nixos) (
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
