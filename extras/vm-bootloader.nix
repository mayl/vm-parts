# Ported from nix-community/nixos-generators (MIT), formats/vm-bootloader.nix.
#
# As ./vm.nix, but the guest boots through its own bootloader rather than having
# the kernel handed to it by qemu -- which is what you want when the thing under
# test is the boot path itself.
{ ... }:
{
  imports = [ ./vm.nix ];

  virtualisation.useBootLoader = true;
}
