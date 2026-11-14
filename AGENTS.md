# vm-parts: notes for agents

A flake-parts module: `vms.<name>` declares a NixOS machine, and each name in
its `formats` becomes a top-level flake output (`nix build .#<name>.<format>`).
README.md is the user-facing reference; read it before changing behaviour.

## Layout

- `flake-module.nix`: the public entry point (`flakeModules.default`).
- `modules/vms.nix`: flake-level options and output wiring.
- `modules/vm-submodule.nix`: the `vms.<name>` submodule, one `extendModules`
  per requested format.
- `modules/registry.nix`: builds and resolves the per-machine format registry
  from nixpkgs' `image.modules`.
- `modules/format-options.nix`: the `format.attr` / `format.filePath` contract.
- `modules/aliases.nix`: nixos-generators names mapped to nixpkgs names.
- `extras/`: formats nixpkgs lacks (`vm*`, `kexec-bundle`).
- `tests/`: the example flake and its checks.

## Commands

```console
$ nix flake check              # eval-only; must stay that way (see below)
$ nix fmt                      # nixfmt-tree; CI fails on any diff
$ nix build .#tests.build-vm   # a real VM build
$ nix build .#tests.kexec-bundle  # NixOS VM test: kexec into the bundle
```

CI (`.github/workflows/ci.yml`) runs `nix flake check`, the format check and
a template smoke test. It does not run the `tests.*` builds; run those yourself
when you touch `extras/`.

## Invariants

- **Laziness.** A format not listed in `formats` must never be evaluated.
  Index the registry (`registry.${name}`, `?`); never traverse it
  (`filterAttrs`, `attrValues`, `mapAttrsToList`) on an unconditional path.
  `attrNames` is fine. `tests/example.nix` plants a `boom` format that throws if
  evaluated; keep that test passing.
- **Checks are eval-only.** `checks.eval` instantiates derivations and
  discards their string context so that `nix flake check` builds nothing.
  Anything that builds an image or boots a VM goes under
  `legacyPackages.<system>.tests`, not `checks`.
- **Warning-free.** CI runs `nix flake check` with `abort-on-warn`. Silence
  a nixpkgs warning at its source; don't let one in.
- **Every bug fix gets a check** in `tests/checks.nix`. Negative cases that
  throw while computing output names need their own `mkTestFlake` evaluation.
