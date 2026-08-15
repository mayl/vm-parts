# Your machine. This is an ordinary NixOS module -- nothing here is specific to
# vm-parts, and the same configuration is used for every format you build.
#
# The format modules supply their own bootloader, filesystem and image plumbing,
# so this file only needs to describe the system you actually want.
{ ... }:
{
  # The qemu run script is named after the hostname, so this is what makes
  # `nix build .#myMachine.vm` produce ./result/bin/run-myMachine-vm.
  networking.hostName = "myMachine";

  users.users.root.initialPassword = "nixos";

  services.openssh.enable = true;

  # Real configuration goes here.

  system.stateVersion = "25.05";
}
