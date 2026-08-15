# Formats with no equivalent in nixpkgs' `image.modules`.
#
# Everything else comes from `image.modules` (see ../modules/registry.nix). These
# four are here because they are not images: the `vm*` formats build
# `system.build.vm`, a run script, and `kexec-bundle` builds a self-extracting
# shell script. Neither fits upstream's "one variant, one `system.build.image`"
# shape, which is why they were left behind when nixos-generators was upstreamed.
#
# Names are chosen not to collide with any `image.modules` variant. A collision
# would not error -- both modules would simply be merged -- but it would be
# surprising.
{
  vm = ./vm.nix;
  vm-nogui = ./vm-nogui.nix;
  vm-bootloader = ./vm-bootloader.nix;
  kexec-bundle = ./kexec-bundle.nix;
}
