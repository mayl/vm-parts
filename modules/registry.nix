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
  # `format.attr` needs nothing: its option default is already `image`.
  # `filePath` is set at `mkDefault`, so that a user's `formatModules.<name>`
  # definition can change it without needing `mkForce`.
  mkImageFormat =
    module:
    { config, lib, ... }:
    {
      imports = [ module ];
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

  # nixos-generators' `sd-aarch64` / `sd-x86_64`, as upstream's `sd-card`
  # pinned to one architecture.
  #
  # Upstream replaced the two with a single `sd-card` variant that picks the
  # per-architecture module from the machine's own platform. An alias from the
  # old names would therefore build an aarch64 image when asked for `sd-x86_64`
  # on an aarch64 machine, without complaint. These wrap the registry's own
  # `sd-card` entry -- so customisations of it still apply -- and fail with an
  # assertion when the machine's architecture does not match the name.
  #
  # LAZINESS: the attribute names are static, so the caller can merge this into
  # the registry it reads from without recursion; `registry.sd-card` is only
  # reached if one of these formats is actually requested.
  archPinnedFormats =
    registry:
    lib.genAttrs' [ "aarch64" "x86_64" ] (
      arch:
      lib.nameValuePair "sd-${arch}" (
        { pkgs, ... }:
        {
          imports = [ registry.sd-card ];
          assertions = [
            {
              assertion = pkgs.stdenv.hostPlatform.qemuArch == arch;
              message = ''
                vm-parts: the `sd-${arch}' format builds an ${arch} SD card image,
                but this machine is ${pkgs.stdenv.hostPlatform.system}. Use `sd-card',
                which follows the machine's architecture.
              '';
            }
          ];
        }
      )
    );

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
