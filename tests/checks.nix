# Checks over ./example.nix.
#
# Everything here is eval-only: it instantiates derivations but never builds a
# disk image, so `nix flake check` stays cheap enough to run in CI. Real builds
# and VM tests live in `buildChecks` (exposed as `legacyPackages.<system>.tests`)
# and are deliberately kept out of the default set.
{
  pkgs,
  example,
  mkTestFlake,
}:
let
  inherit (pkgs) lib;

  assertMsg = cond: msg: lib.assertMsg cond "vm-parts check failed: ${msg}";

  vboxConfig = example.inlineMachine.vbox.config;
  overrideConfig = example.overrideMachine.vbox.config;

  # A machine whose name collides with a standard flake output. It gets its own
  # flake evaluation because the guard throws while computing output attribute
  # names, which would take the whole example down with it.
  reservedNameFlake = mkTestFlake {
    vms.packages = {
      system = "x86_64-linux";
      modules = [ ];
      formats = [ "vm" ];
    };
  };

  # Two machines claiming one output name. `listToAttrs` would silently keep
  # one of them, so this must throw instead.
  duplicateNameFlake = mkTestFlake {
    vms = {
      a = {
        system = "x86_64-linux";
        outputName = "same";
        formats = [ "vm" ];
      };
      b = {
        system = "x86_64-linux";
        outputName = "same";
        formats = [ "vm" ];
      };
    };
  };

  # Another flake module declares a `customOutput` flake output; a machine may
  # not take that name either.
  declaredOutputFlake = mkTestFlake {
    imports = [
      {
        options.flake = lib.mkOption {
          type = lib.types.submoduleWith {
            modules = [ { options.customOutput = lib.mkOption { default = null; }; } ];
          };
        };
      }
    ];
    vms.x = {
      system = "x86_64-linux";
      outputName = "customOutput";
      formats = [ "vm" ];
    };
  };

  # Exporting an adopted configuration would define its nixosConfigurations
  # entry twice; refused with a vm-parts error instead.
  adoptedExportFlake = mkTestFlake {
    vms.adopted = {
      nixos = example.adoptedMachine.vm.nixos;
      formats = [ "vm" ];
      exportNixosConfiguration = true;
    };
  };

  units = [
    # An alias resolves to the upstream `image.modules` variant.
    (assertMsg (vboxConfig.image.extension == "ova")
      "the `vbox' alias should resolve to the virtualbox image variant, got extension ${vboxConfig.image.extension}"
    )

    # ...and the resulting output carries the artifact symlink.
    (assertMsg (example.inlineMachine.vbox ? file) "an image format should expose a .file attribute")

    # A run-script format has no single artifact, so no .file.
    (assertMsg (
      !(example.inlineMachine.vm ? file)
    ) "a run-script format should not expose a .file attribute")
    (assertMsg (
      example.inlineMachine.vm.config.format.attr == "vm"
    ) "the vm format should build system.build.vm")

    # Customising a built-in merges into it rather than replacing it: the name
    # changes, but it is still the virtualbox variant producing an .ova.
    (assertMsg (lib.hasInfix "custom-name" overrideConfig.image.fileName) "formatModules.virtualbox should have customised image.baseName, got ${overrideConfig.image.fileName}")
    (assertMsg (
      overrideConfig.image.extension == "ova"
    ) "customising virtualbox should not have replaced the underlying variant")

    # nixosConfigurations are opt-in: a format-agnostic machine stays out of the
    # output (it has no valid standalone toplevel), and so does an adopted one.
    (assertMsg (
      !(example.nixosConfigurations ? inlineMachine)
    ) "a format-agnostic machine should not be exported as a nixosConfiguration")
    (assertMsg (
      !(example.nixosConfigurations ? adoptedMachine)
    ) "an adopted nixos configuration should not be re-exported")
    (assertMsg (
      example.nixosConfigurations ? standaloneMachine
    ) "exportNixosConfiguration = true should export the machine")

    # Unknown formats fail, and say what is available.
    (assertMsg (
      !(builtins.tryEval example.brokenMachine.definitely-not-a-format).success
    ) "requesting an undefined format should throw")

    # A machine named after a standard flake output is refused up front, rather
    # than silently shadowing the real one.
    (assertMsg (
      !(builtins.tryEval (builtins.attrNames reservedNameFlake)).success
    ) "a machine named `packages' should be refused")

    # A machine named after an output that some other flake module declares
    # (not in vm-parts' static list) is refused too.
    (assertMsg (
      !(builtins.tryEval (builtins.attrNames declaredOutputFlake)).success
    ) "an outputName matching a declared flake output should be refused")

    # Two machines sharing an output name are refused, not silently merged.
    (assertMsg (
      !(builtins.tryEval (builtins.attrNames duplicateNameFlake)).success
    ) "two machines with the same outputName should be refused")

    # `outputName` governs both the format outputs and the nixosConfigurations
    # entry.
    (assertMsg (
      example ? renamed && !(example ? renamedMachine)
    ) "outputName should rename the top-level output")
    (assertMsg (
      example.nixosConfigurations ? renamed && !(example.nixosConfigurations ? renamedMachine)
    ) "exportNixosConfiguration should export under outputName")

    (assertMsg (
      !(builtins.tryEval (builtins.attrNames adoptedExportFlake.nixosConfigurations)).success
    ) "exportNixosConfiguration on an adopted nixos should throw")

    # Flake-level formatModules are re-exported, and only those.
    (assertMsg (
      lib.attrNames example.formatModules == [ "shared-iso" ]
    ) "formatModules should re-export exactly the flake-level definitions")

    # User aliases resolve, and a user definition overrides a built-in alias.
    (assertMsg (
      example.aliasMachine.my-vbox.config.image.extension == "ova"
    ) "a user-defined alias should resolve")
    (assertMsg (
      example.aliasMachine.gce.config.image.extension == "qcow2"
    ) "a user formatAliases definition should override the built-in alias")

    # Architecture-pinned SD card formats.
    (assertMsg (lib.hasPrefix "img" example.sdMachine.sd-x86_64.config.image.extension) "sd-x86_64 should be the sd-card image variant on an x86_64 machine")
    (assertMsg (
      !(builtins.tryEval example.sdMachine.sd-aarch64.drvPath).success
    ) "sd-aarch64 on an x86_64 machine should fail its architecture assertion")

    # The opt-in `packages` mirror: exactly the requested formats of the machines
    # that opted in, and nothing for anyone else.
    (assertMsg
      (
        lib.attrNames example.packages.x86_64-linux == [
          "inlineMachine-iso"
          "inlineMachine-kexec-bundle"
          "inlineMachine-vbox"
          "inlineMachine-vm"
          "inlineMachine-vm-nogui"
        ]
      )
      "exposeAsPackages should mirror exactly the requested formats, got ${toString (lib.attrNames example.packages.x86_64-linux)}"
    )
    (assertMsg (
      example.packages.x86_64-linux.inlineMachine-vm.drvPath == example.inlineMachine.vm.drvPath
    ) "a mirrored package should be the same derivation as the top-level output")

    # Laziness: `boom` sits in inlineMachine's registry and would throw if it were
    # ever evaluated. Reaching a different format must not touch it. This is the
    # regression test for the invariant that the registry is indexed, never
    # traversed -- a stray filterAttrs over it would break this and nothing else.
    (assertMsg (example.inlineMachine.vm ? drvPath) "an unrequested format must never be evaluated")
  ];
in
{
  checks = {
    # Instantiates every example format, building none of them.
    #
    # `drv.drvPath` carries string context, so embedding it directly would make
    # every listed format a build-time dependency of this check -- `nix flake
    # check` would then build an ISO and a VirtualBox appliance, which is exactly
    # what this check exists to avoid. Discarding the context keeps the
    # instantiation (evaluating `drvPath` still writes the .drv) while dropping
    # the build edge.
    eval = builtins.seq (lib.all (x: x) units) (
      pkgs.writeText "vm-parts-example-drvpaths" (
        lib.concatMapStringsSep "\n" builtins.unsafeDiscardStringContext [
          example.inlineMachine.vm.drvPath
          example.inlineMachine.vm-nogui.drvPath
          example.inlineMachine.vbox.drvPath
          example.inlineMachine.vbox.file.drvPath
          example.inlineMachine.iso.drvPath
          example.inlineMachine.kexec-bundle.drvPath
          example.adoptedMachine.vm.drvPath
          example.standaloneMachine.vm-bootloader.drvPath
          example.overrideMachine.vbox.drvPath
          example.renamed.vm.drvPath
          example.sdMachine.sd-x86_64.drvPath
        ]
      )
    );
  };

  # Real builds. Expensive; wired up separately, not part of `nix flake check`.
  buildChecks = {
    build-vm = example.inlineMachine.vm;
    kexec-bundle = import ./kexec-bundle.nix { inherit pkgs; };
  };
}
