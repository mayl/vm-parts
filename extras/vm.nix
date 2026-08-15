# Ported from nix-community/nixos-generators (MIT), formats/vm.nix.
#
# Builds `system.build.vm`: a script that boots the configuration under qemu with
# a throwaway disk image. Not an image, so it has no `format.filePath`.
{ lib, modulesPath, ... }:
{
  imports = [ "${toString modulesPath}/virtualisation/qemu-vm.nix" ];

  virtualisation.diskSize = lib.mkDefault (2 * 1024);

  format.attr = "vm";
  format.filePath = null;
}
