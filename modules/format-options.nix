# NixOS module merged into every format evaluation.
#
# This is the one indirection that nixpkgs' `image.modules` infrastructure does
# not provide. Upstream assumes every variant produces `system.build.image` and
# describes its artifact with `image.filePath`. That assumption holds for disk
# images but not for the qemu *run script* formats (`vm`, `vm-nogui`,
# `vm-bootloader`), which produce `system.build.vm` and have no artifact file at
# all. `format.attr` / `format.filePath` generalise over both.
#
# It is the direct descendant of nixos-generators' `formatAttr` / `fileExtension`.
{ lib, ... }:
{
  _file = ./format-options.nix;

  # Deliberate key, so that the module is deduplicated no matter which path it is
  # reached by (the flake's store path differs between consumers).
  key = "vm-parts/format-options.nix";

  options.format = {
    attr = lib.mkOption {
      type = lib.types.str;
      default = "image";
      example = "vm";
      description = ''
        Attribute under `system.build` holding this format's output.

        Defaults to `image`, which is what every nixpkgs `image.modules` variant
        sets. Formats that build something other than a disk image override it.
      '';
    };

    filePath = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      # IMPORTANT: do not default this to `config.image.filePath`.
      #
      # `image.filePath` defaults to `image.fileName`, which defaults to
      # `"${image.baseName}.${image.extension}"`, and `image.extension` has *no*
      # default. Reading it from a format that is not an image -- `vm`, say --
      # therefore throws "option `image.extension' is used but not defined"
      # rather than yielding null. The image-derived registry entries in
      # ./registry.nix set this explicitly instead, where it is known to be safe.
      default = null;
      example = "nixos.ova";
      description = ''
        Path of the single primary artifact, relative to `$out` of the format's
        derivation, or `null` when the format has no single artifact file.

        When non-null, the format output gains a `.file` attribute: a symlink
        pointing directly at this artifact, so that `nix build .#machine.fmt.file`
        leaves `result` pointing at the file itself rather than a directory.
      '';
    };
  };
}
