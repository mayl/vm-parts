# Construction of the per-machine format registry.
#
# nixpkgs already ships DavHau's nixos-generators design as
# `nixos/modules/image/images.nix`: `image.modules :: attrsOf deferredModule`,
# one `extendModules` per variant, results at `system.build.images.<variant>`.
# Rather than vendoring a frozen copy of the ~30 nixos-generators format modules,
# we read `image.modules` straight off the machine. Every upstream variant is
# available for free, and new ones appear on a nixpkgs bump with no change here.
{ lib }:
rec {
  # Adapt a nixpkgs `image.modules` entry to the ./format-options.nix contract.
  #
  # `mkDefault` on both, so that a user's `formatModules.<name>` definition can
  # change either without needing `mkForce`.
  mkImageFormat =
    module:
    { config, lib, ... }:
    {
      imports = [ module ];
      format.attr = lib.mkDefault "image";
      # Safe here, unlike in format-options.nix: this configuration *is* an image,
      # so `image.extension` is defined by the module we just imported.
      format.filePath = lib.mkDefault config.image.filePath;
    };

  # The `image.modules` variants of a machine, adapted, keyed by variant name.
  #
  # LAZINESS: `mapAttrs` forces attribute *names* only. Neither `mkImageFormat`
  # nor the modules it wraps are evaluated until a specific name is indexed.
  imageFormats =
    { name, nixos }:
    let
      modules =
        nixos.config.image.modules or (throw ''
          vm-parts: vms.${name} was evaluated against a nixpkgs without the
          `image.modules` option, so no image formats can be discovered.

          `image.modules` was added in NixOS 25.05. Either use a newer nixpkgs,
          or define the formats you need explicitly via `formatModules`.
        '');
    in
    lib.mapAttrs (_: mkImageFormat) modules;

  # Resolve a user-facing format name against a registry.
  #
  # A name present in the registry always wins over an alias, so that a
  # user-defined format called `vbox` shadows the compatibility alias rather than
  # being shadowed by it.
  #
  # LAZINESS: `?` and `attrNames` force attribute names only. `attrNames` appears
  # solely on the error path.
  resolve =
    {
      name,
      registry,
      aliases,
      format,
    }:
    let
      resolved = if registry ? ${format} then format else aliases.${format} or format;
      aliasNote = lib.optionalString (resolved != format) " (via the alias `${format}' -> `${resolved}')";
    in
    registry.${resolved} or (throw ''
      vm-parts: vms.${name} requests the format `${format}'${aliasNote}, which is not defined.

      Available formats: ${lib.concatStringsSep ", " (lib.attrNames registry)}
    '');
}
