# vm-parts

A [flake-parts](https://flake.parts) module that turns NixOS machines into
buildable, multi-format flake outputs:

```console
$ nix build .#myMachine.vm && ./result/bin/run-myMachine-vm
$ nix build .#myMachine.vbox        # a directory containing the .ova
$ nix build .#myMachine.vbox.file   # result *is* the .ova
```

(The qemu run script is named after `networking.hostName`, not after the `vms`
attribute — so it is `run-nixos-vm` unless you set a hostname.)

## Quick start

```console
$ nix flake init -t github:mayl/vm-parts
$ nix build .#myMachine.vm
$ ./result/bin/run-myMachine-vm
```

Or, in an existing flake-parts flake:

```nix
{
  inputs.vm-parts.url = "github:mayl/vm-parts";

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [ inputs.vm-parts.flakeModules.default ];
      systems = [ "x86_64-linux" ];

      vms.myMachine = {
        system = "x86_64-linux";
        modules = [ ./machine.nix ];
        formats = [ "vm" "vbox" "iso" ];
      };
    };
}
```

`./machine.nix` describes the *system*. Bootloader, filesystems and partitioning
come from the format — that separation is what lets one configuration build many
ways.

## Relationship to nixos-generators

[nixos-generators](https://github.com/nix-community/nixos-generators) was
archived on 2026-01-30, but its `all-formats.nix` module was not lost — it was
upstreamed. `nixos/modules/image/images.nix` in nixpkgs is DavHau's design
essentially verbatim: `image.modules :: attrsOf deferredModule`, one
`extendModules` per variant, results under `system.build.images.<variant>`.

Three things did not make the trip, and are what this module supplies:

1. **Flake-output plumbing.** Upstream gives you
   `nixosConfigurations.x.config.system.build.images.y`, or
   `nixos-rebuild build-image`. Not `nix build .#x.y`.
2. **The qemu run-script formats.** `vm`, `vm-nogui` and `vm-bootloader` build
   `system.build.vm`, a script, not `system.build.image`. They did not fit
   upstream's shape, so they live in [`extras/`](./extras) here.
3. **The old names.** `vbox`, `qcow`, `gce` and friends were renamed upstream.
   See the migration table below.

Everything else is read straight off the machine's own `image.modules`, so new
nixpkgs variants become available on a bump with no change here.

## Options

### `vms.<name>`

| Option | Type | Default | Meaning |
|---|---|---|---|
| `formats` | list of string | *required* | Exactly the formats to expose. Each becomes `<outputName>.<format>`. |
| `modules` | list | `[]` | NixOS modules for the machine. |
| `system` | null or string | `null` | Shorthand for `nixpkgs.hostPlatform`. |
| `specialArgs` | attrs | `{}` | Passed to `nixosSystem`. Nothing is injected implicitly. |
| `nixpkgs` | flake | `inputs.nixpkgs` | Which nixpkgs to evaluate against. |
| `nixos` | raw | *built from the above* | Assign to adopt an already-evaluated configuration. |
| `formatModules` | attrs of module | `{}` | Per-machine format registry additions and customisations. |
| `outputName` | string | the attribute name | Flake output attribute to appear under. |
| `exportNixosConfiguration` | bool | `false` | Also expose as `nixosConfigurations.<outputName>`. |
| `exposeAsPackages` | bool | `false` | Also expose each format as `packages.<system>.<outputName>-<format>`, for `nix flake show`. |

`specialArgs` is empty by default — if your modules expect an `inputs` argument,
pass it yourself:

```nix
vms.myMachine.specialArgs = { inherit inputs; };
```

`exportNixosConfiguration` is off by default because a format-agnostic machine
has no valid standalone `system.build.toplevel`; exporting one would give you a
`nixosConfigurations` entry that fails `nix flake check`. Turn it on for machines
that are also complete systems. Turning it on for a machine whose `nixos` you
assigned directly is an error: export that configuration from wherever it is
defined instead.

When `nixos` is assigned directly, `modules`, `system` and `specialArgs` have no
effect, and setting them produces an evaluation warning saying so.

### Flake-level

| Option | Type | Meaning |
|---|---|---|
| `formatModules` | attrs of module | Formats available to every machine. Also re-exported as the `formatModules` flake output. |
| `formatAliases` | attrs of string | Alternative names, resolved when a name is not in the registry. Pre-populated with the nixos-generators names. |

## Adopting an existing configuration

```nix
flake.nixosConfigurations.myMachine = inputs.nixpkgs.lib.nixosSystem { ... };

vms.myMachine = {
  nixos = config.flake.nixosConfigurations.myMachine;
  formats = [ "iso" ];
};
```

Formats are produced by calling `extendModules` on `nixos`, so both routes behave
identically from that point on.

## Adding your own format

A format is an ordinary NixOS module that also says which `system.build`
attribute it produces.

```nix
formatModules.my-appliance = { config, modulesPath, ... }: {
  imports = [ "${modulesPath}/virtualisation/disk-image.nix" ];
  image.format = "raw";

  format.attr = "image";                    # default; which system.build attr to build
  format.filePath = config.image.filePath;  # optional; enables `.file`
};
```

For an image-shaped format, take `format.filePath` from `config.image.filePath`
rather than writing the filename out — that keeps `.file` in step with
`image.baseName` and `image.extension` instead of drifting from them. For a
format that produces no single artifact (a run script, say), leave it `null`.

Defining a name that already exists **customises** it rather than replacing it —
the module system merges the definitions. This is how nixos-generators'
`formatConfigs` behaved:

```nix
# still the virtualbox variant, still produces an .ova, just renamed
vms.myMachine.formatModules.virtualbox.image.baseName = "my-appliance";
```

Use `lib.mkForce` when you really do want to override rather than extend.

## Migration from nixos-generators

Renamed upstream; the old name works as an alias:

| nixos-generators | nixpkgs `image.modules` |
|---|---|
| `vbox` | `virtualbox` |
| `qcow` | `qemu` |
| `qcow-efi` | `qemu-efi` |
| `do` | `digital-ocean` |
| `gce` | `google-compute` |
| `install-iso` | `iso-installer` |

Unchanged: `amazon`, `azure`, `cloudstack`, `hyperv`, `iso`, `kubevirt`,
`linode`, `lxc`, `lxc-metadata`, `openstack`, `proxmox`, `proxmox-lxc`, `raw`,
`raw-efi`, `vagrant-virtualbox`, `virtualbox`, `vmware`.

No upstream equivalent, shipped in [`extras/`](./extras): `vm`, `vm-nogui`,
`vm-bootloader`, `kexec-bundle`.

`sd-aarch64` and `sd-x86_64` still work, but they are not plain aliases. Upstream
replaced them with a single `sd-card` that follows the machine's architecture,
so these wrap `sd-card` and fail with an assertion when the machine's
architecture doesn't match the name. On new configurations, use `sd-card`.

Watch out for `kexec`: nixpkgs has a variant by that name, but it is the netboot
payload, not nixos-generators' tarball. The self-extracting bundle is
`kexec-bundle` here.

`kexec-bundle` usage: put a public key at `/ssh_pubkey` on the host you are
taking over, run the bundle as root, and the new system boots with that key in
root's `authorized_keys`. The bundle unpacks its closure into `/nix/store`, so
the host's `/nix/store` must be writable or absent. That rules out a NixOS host
with the default read-only store mount.

### Discovering what is available

`nix build .#myMachine.nope` only gets you nix's generic "does not provide
attribute" — outputs exist for the formats you listed and nothing else. To see
every format a machine *could* build, put a bogus name in `formats`:

```nix
vms.myMachine.formats = [ "vm" "nope" ];
```

```
error: vm-parts: vms.myMachine requests the format `nope', which is not defined.

Available formats: amazon, azure, cloudstack, digital-ocean, google-compute,
hyperv, iso, iso-installer, kexec, kexec-bundle, kubevirt, linode, lxc,
lxc-metadata, oci, openstack, openstack-zfs, proxmox, proxmox-lxc, qemu,
qemu-efi, raw, raw-efi, sd-card, vagrant-virtualbox, virtualbox, vm,
vm-bootloader, vm-nogui, vmware
```

The list is that machine's own `image.modules` plus `extras/` plus anything you
defined, so it reflects your nixpkgs rather than this README.

## Laziness

A format not named in `formats` is never evaluated — only its attribute *name* is
ever forced. Declaring `formats = [ "vm" ]` runs one `extendModules` fixpoint,
not one per `image.modules` variant.

This holds by construction, but it is fragile: the registry must be **indexed,
never traversed**. A `filterAttrs`, `attrValues` or `mapAttrsToList` over it in
an unconditional code path would quietly evaluate every format on every
`nix build`. `attrNames` is fine, and appears only on the "unknown format" error
path. There is a regression test for this in [`tests/`](./tests) that plants a
module which throws if evaluated.

## Outputs

Machines land at the **top level** of the flake, which is what makes
`nix build .#myMachine.vm` work literally. Two consequences, both deliberate:

- The outputs are not partitioned by system, so `nix flake check` warns about an
  unknown top-level output (a warning, not a failure), and `nix flake show`
  lists the machine as `unknown` without naming its formats. Set
  `exposeAsPackages = true` on a machine to also get
  `packages.<system>.<outputName>-<format>`, which `nix flake show` lists by
  name. The cost: `nix flake show` and `nix flake check` then evaluate every
  format in that machine's `formats`. Formats you didn't list are still never
  evaluated.
- A machine named after a standard flake output (`packages`, `checks`, `lib`,
  or any output another flake module declares) is refused up front, and so are
  two machines with the same `outputName`. Use `outputName` to rename one.

## Development

```console
$ nix flake check                  # eval-only: instantiates every format, builds none
$ nix build .#tests.build-vm       # a real VM build, kept out of flake check
$ nix build .#tests.kexec-bundle   # NixOS VM test: kexec into the bundle, check the SSH key hand-off
$ nix fmt
```

## License

MIT. `extras/` is derived from nix-community/nixos-generators, also MIT.
