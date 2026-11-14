{
  description = "A NixOS machine, buildable in several image formats";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";

    vm-parts.url = "github:mayl/vm-parts";
    vm-parts.inputs.nixpkgs.follows = "nixpkgs";
    vm-parts.inputs.flake-parts.follows = "flake-parts";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.vm-parts.flakeModules.default ];

      systems = [ "x86_64-linux" ];

      vms.myMachine = {
        system = "x86_64-linux";
        modules = [ ./machine.nix ];

        # Every name here becomes a buildable output: nix build .#myMachine.vm
        #
        #   vm        a qemu run script  -> ./result/bin/run-myMachine-vm
        #   vbox      VirtualBox .ova    (alias for the `virtualbox` variant)
        #   iso       bootable ISO
        #
        # To see every format this machine could build, add a bogus name here --
        # the error lists all of them.
        formats = [
          "vm"
          "vbox"
          "iso"
        ];
      };
    };
}
