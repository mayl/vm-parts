# Dogfood evaluation, used by the flake's checks.
#
# This is a plain function rather than a sub-flake. The usual trick for testing a
# flake from within itself (nixos-generators' `callFlake`, which imports the
# sub-flake and passes `self = subFlake`) does not survive contact with
# flake-parts: `mkFlake`'s `moduleLocation` argument defaults to
# "${self.outPath}/flake.nix", and forcing that on a self-referential attrset
# with no `outPath` fails. Passing `inputs.self` and `moduleLocation` explicitly
# sidesteps the whole problem.
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
    users.users.root.initialPassword = "vm-parts";
    services.openssh.enable = true;
    system.stateVersion = "25.05";
  };

  # A machine that is also a complete system, so it can be exported for
  # nixos-rebuild.
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
inputs.flake-parts.lib.mkFlake
  {
    inputs = inputs // {
      self = {
        outPath = ./.;
        _type = "flake";
      };
    };
    moduleLocation = ./example.nix;
  }
  {
    imports = [ ../flake-module.nix ];
    systems = [ system ];

    # A format defined once, for every machine.
    formatModules.shared-iso =
      { modulesPath, ... }:
      {
        imports = [ "${toString modulesPath}/installer/cd-dvd/installation-cd-base.nix" ];
        format.attr = "image";
      };

    vms = {
      # Built from modules, formats reached partly through an alias.
      inlineMachine = {
        inherit system;
        modules = [ base ];
        formats = [
          "vm"
          "vbox"
          "iso"
        ];

        # Never requested, and must never be evaluated.
        formatModules.boom = poison "boom";
      };

      # Adopted from an already-evaluated configuration.
      adoptedMachine = {
        nixos = adopted;
        formats = [ "vm" ];
      };

      # Opted in to a nixosConfigurations export, which it can afford because it
      # describes a complete system.
      standaloneMachine = {
        inherit system;
        modules = [ standalone ];
        formats = [ "vm" ];
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

      # Only ever referenced from inside tryEval, to check the error path.
      brokenMachine = {
        inherit system;
        modules = [ base ];
        formats = [ "definitely-not-a-format" ];
      };
    };
  }
