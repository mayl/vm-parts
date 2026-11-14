# Dogfood evaluation, used by the flake's checks.
{ inputs }:
let
  inherit (inputs.nixpkgs) lib;

  system = "x86_64-linux";

  # A format-agnostic machine: no bootloader, no filesystems, no partitioning.
  # Those come from whichever format is being built, which is what makes one
  # configuration buildable many ways. It is deliberately *not* a valid standalone
  # nixosConfiguration -- see `standaloneMachine` below for that case.
  base = {
    nixpkgs.hostPlatform = system;
    services.openssh.enable = true;
    system.stateVersion = "25.05";
  };

  # A machine that is also a complete system, so it can be exported for
  # nixos-rebuild -- and so it can boot its own bootloader, which `vm-bootloader`
  # requires.
  standalone = {
    imports = [ base ];
    boot.loader.grub.device = "/dev/sda";
    fileSystems."/" = {
      device = "/dev/disk/by-label/nixos";
      fsType = "ext4";
    };
  };

  # A machine that already exists as a nixosConfiguration, to exercise the
  # "adopt an existing configuration" path.
  adopted = lib.nixosSystem { modules = [ base ]; };

  # Poison. A *function* module, not a bare `throw`: `types.deferredModule`'s
  # check forces every definition to weak head normal form, so a bare `throw`
  # would fire on the type check rather than on evaluation and would prove
  # nothing. A function passes `isFunction` untouched and only explodes if some
  # code path actually evaluates the module.
  poison = name: { ... }: throw "vm-parts: unrequested format `${name}' was evaluated";
in
import ./mkflake.nix { inherit inputs; } {
  # A format defined once, for every machine.
  formatModules.shared-iso =
    { modulesPath, ... }:
    {
      imports = [ "${toString modulesPath}/installer/cd-dvd/installation-cd-base.nix" ];
      format.attr = "image";
    };

  # A user alias, and a user override of a built-in one (`gce` normally means
  # `google-compute`).
  formatAliases = {
    my-vbox = "virtualbox";
    gce = "qemu";
  };

  vms = {
    # Built from modules, formats reached partly through an alias.
    #
    # `vm-nogui` and `kexec-bundle` are here purely for coverage: they are two of
    # the four formats this project vendors itself (nixpkgs has no equivalent), so
    # nothing but these checks would notice a nixpkgs bump breaking them.
    # `kexec-bundle` especially -- it reaches into nixpkgs internals.
    inlineMachine = {
      inherit system;
      modules = [ base ];
      formats = [
        "vm"
        "vm-nogui"
        "vbox"
        "iso"
        "kexec-bundle"
      ];

      # Never requested, and must never be evaluated -- including when the
      # formats are mirrored into `packages`.
      formatModules.boom = poison "boom";
      exposeAsPackages = true;
    };

    # Adopted from an already-evaluated configuration.
    adoptedMachine = {
      nixos = adopted;
      formats = [ "vm" ];
    };

    # Opted in to a nixosConfigurations export, which it can afford because it
    # describes a complete system. `vm-bootloader` lives here rather than on
    # `inlineMachine` for the same reason: booting through your own bootloader
    # requires having one.
    standaloneMachine = {
      inherit system;
      modules = [ standalone ];
      formats = [
        "vm"
        "vm-bootloader"
      ];
      exportNixosConfiguration = true;
    };

    # Customising a built-in: this merges into the `image.modules` virtualbox
    # variant rather than replacing it.
    overrideMachine = {
      inherit system;
      modules = [ base ];
      formats = [ "vbox" ];
      formatModules.virtualbox.image.baseName = "custom-name";
    };

    # `outputName` must govern every output the machine produces, including the
    # nixosConfigurations entry.
    renamedMachine = {
      inherit system;
      modules = [ standalone ];
      outputName = "renamed";
      formats = [ "vm" ];
      exportNixosConfiguration = true;
    };

    # Formats reached only through user-defined and user-overridden aliases.
    aliasMachine = {
      inherit system;
      modules = [ base ];
      formats = [
        "my-vbox"
        "gce"
      ];
    };

    # The architecture-pinned SD card formats: the matching one works, the
    # other must refuse rather than quietly build an x86_64 image.
    sdMachine = {
      inherit system;
      modules = [
        base
        # The sd-card variant enables ZFS, and nixpkgs warns until this is set.
        { boot.zfs.forceImportRoot = false; }
      ];
      formats = [
        "sd-x86_64"
        "sd-aarch64"
      ];
    };

    # Only ever referenced from inside tryEval, to check the error path.
    brokenMachine = {
      inherit system;
      modules = [ base ];
      formats = [ "definitely-not-a-format" ];
    };
  };
}
