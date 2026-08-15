{
  description = "Declare NixOS machines in flake-parts and build them in many image formats";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-parts.inputs.nixpkgs-lib.follows = "nixpkgs";
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        flake-parts.flakeModules.flakeModules
        # Dogfood: the option declarations are type-checked by our own eval.
        ./flake-module.nix
      ];

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      flake.flakeModules.default = ./flake-module.nix;

      flake.templates =
        let
          template = {
            path = ./template;
            description = "A flake-parts flake with one NixOS machine, buildable in several formats.";
            welcomeText = ''
              # vm-parts

              One machine is declared in `flake.nix` under `vms.myMachine`. Build it:

                  nix build .#myMachine.vm && ./result/bin/run-myMachine-vm
                  nix build .#myMachine.vbox        # VirtualBox .ova, in a directory
                  nix build .#myMachine.vbox.file   # the .ova itself

              Add formats by listing them in `vms.myMachine.formats`.
            '';
          };
        in
        {
          default = template;
          vm-parts = template;
        };

      perSystem =
        { pkgs, system, ... }:
        let
          example = import ./tests/example.nix { inherit inputs; };
          mkTestFlake = import ./tests/mkflake.nix { inherit inputs; };
          tests = import ./tests/checks.nix { inherit pkgs example mkTestFlake; };
          nixfmt = pkgs.nixfmt-tree or pkgs.nixfmt-rfc-style or pkgs.nixfmt;
        in
        {
          formatter = nixfmt;
          devShells.default = pkgs.mkShell { packages = [ nixfmt ]; };

          # The example machines are x86_64-linux, so the checks only exist there.
          checks = pkgs.lib.optionalAttrs (system == "x86_64-linux") tests.checks;

          # Real image builds, deliberately outside `checks` so that
          # `nix flake check` does not build a disk image. Run explicitly:
          #   nix build .#build-vm
          packages = pkgs.lib.optionalAttrs (system == "x86_64-linux") tests.buildChecks;
        };
    };
}
