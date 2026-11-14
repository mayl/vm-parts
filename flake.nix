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

      # Only the formatter and dev tooling are per-system; the `vms` outputs
      # are not. x86_64-darwin is deliberately absent: nixpkgs 26.11 dropped
      # it, and listing it makes `nix flake show` fail outright.
      systems = [
        "x86_64-linux"
        "aarch64-linux"
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
        in
        {
          formatter = pkgs.nixfmt-tree;

          # The example machines are x86_64-linux, so the tests only exist there.
          checks = pkgs.lib.optionalAttrs (system == "x86_64-linux") tests.checks;

          # Real builds and VM tests, deliberately outside `checks` so that
          # `nix flake check` never builds a disk image. Under `legacyPackages`
          # rather than `packages` so they are not advertised as things this
          # flake provides. Run explicitly:
          #   nix build .#tests.build-vm
          #   nix build .#tests.kexec-bundle
          legacyPackages = pkgs.lib.optionalAttrs (system == "x86_64-linux") {
            tests = tests.buildChecks;
          };
        };
    };
}
