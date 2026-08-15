# vm-parts: the flake-parts module.
#
# Import this into your flake-parts flake:
#
#   imports = [ inputs.vm-parts.flakeModules.default ];
#
#   vms.myMachine = {
#     system = "x86_64-linux";
#     modules = [ ./machine.nix ];
#     formats = [ "vm" "vbox" "iso" ];
#   };
#
# and then `nix build .#myMachine.vm`.
{
  _class = "flake";
  imports = [ ./modules/vms.nix ];
}
