# Evaluate a flake-parts flake that imports this module, for tests.
#
# Factored out so that checks needing their *own* flake evaluation (the
# reserved-output-name guard, which throws while computing output attribute names
# and so cannot live alongside the working machines) share one definition with
# ./example.nix.
#
# This is a plain function rather than a sub-flake. The usual trick for testing a
# flake from within itself (nixos-generators' `callFlake`, which imports the
# sub-flake and passes `self = subFlake`) does not survive contact with
# flake-parts: `mkFlake`'s `moduleLocation` argument defaults to
# "${self.outPath}/flake.nix", and forcing that on a self-referential attrset with
# no `outPath` fails. Passing `self` and `moduleLocation` explicitly sidesteps the
# whole problem.
{ inputs }:
module:
inputs.flake-parts.lib.mkFlake
  {
    inputs = inputs // {
      self = {
        outPath = ./.;
        _type = "flake";
      };
    };
    moduleLocation = ./mkflake.nix;
  }
  {
    imports = [
      ../flake-module.nix
      module
    ];
    systems = [ "x86_64-linux" ];
  }
