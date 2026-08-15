# Checks over ./example.nix.
#
# Everything here is eval-only: it instantiates derivations but never builds a
# disk image, so `nix flake check` stays cheap enough to run in CI. The one real
# build lives in `buildChecks` and is deliberately kept out of the default set.
{ pkgs, example }:
let
  inherit (pkgs) lib;

  # Force derivations into existence without building them.
  #
  # `drv.drvPath` carries string context, so embedding it directly would make
  # every listed format a build-time dependency of this check -- `nix flake check`
  # would then build an ISO and a VirtualBox appliance, which is precisely what
  # this check exists to avoid. Discarding the context keeps the instantiation
  # (evaluating `drvPath` still writes the .drv) while dropping the build edge.
  drvPaths =
    name: paths:
    pkgs.writeText "vm-parts-${name}" (
      lib.concatMapStringsSep "\n" builtins.unsafeDiscardStringContext paths
    );

  assertMsg = cond: msg: if cond then true else throw "vm-parts check failed: ${msg}";

  vboxConfig = example.inlineMachine.vbox.config;
  overrideConfig = example.overrideMachine.vbox.config;

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
    eval = builtins.seq (lib.all (x: x) units) (
      drvPaths "example-drvpaths" [
        example.inlineMachine.vm.drvPath
        example.inlineMachine.vbox.drvPath
        example.inlineMachine.vbox.file.drvPath
        example.inlineMachine.iso.drvPath
        example.adoptedMachine.vm.drvPath
        example.overrideMachine.vbox.drvPath
      ]
    );
  };

  # Real builds. Expensive; wired up separately, not part of `nix flake check`.
  buildChecks = {
    build-vm = example.inlineMachine.vm;
  };
}
