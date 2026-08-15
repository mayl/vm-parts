# Compatibility aliases: nixos-generators format names -> nixpkgs `image.modules`
# variant names.
#
# When nixos-generators was upstreamed, several formats were renamed. These
# aliases keep the names people already have in their notes and scripts working,
# including the `vbox` that most nixos-generators users type by reflex.
#
# Users may add to or override this map via the `formatAliases` option; every
# entry here is a `mkDefault`. A name that exists in the format registry always
# takes precedence over an alias of the same name.
{
  vbox = "virtualbox";
  do = "digital-ocean";
  gce = "google-compute";
  install-iso = "iso-installer";

  # nixos-generators' `qcow`/`qcow-efi` built qcow2 via make-disk-image with a
  # hybrid partition table; upstream's `qemu`/`qemu-efi` use
  # virtualisation/disk-image.nix. The output format matches, the partitioning
  # details may not.
  qcow = "qemu";
  qcow-efi = "qemu-efi";

  # Upstream has a single `sd-card` variant that selects the per-architecture
  # module from `pkgs.targetPlatform.qemuArch`, replacing the two explicit ones.
  sd-aarch64 = "sd-card";
  sd-x86_64 = "sd-card";
}
