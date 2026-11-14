# Boot test for extras/kexec-bundle.nix: run the bundle on one machine and
# check that it kexecs into the bundled system with the SSH key handed over.
#
# Modelled on nixpkgs' nixos/tests/kexec.nix. `target` is never booted as its
# own VM; it exists only so that its kexec bundle is built from a configuration
# the test driver can talk to (test instrumentation, same disks and shares as
# `machine`). The bundle is run on `machine`, which then *becomes* `target`.
#
# Expensive (two kernels, a squashfs of the whole closure), so it is exposed as
# `legacyPackages.x86_64-linux.tests.kexec-bundle` rather than as a check:
#
#   nix build .#tests.kexec-bundle
{ pkgs }:
pkgs.testers.runNixOSTest {
  name = "vm-parts-kexec-bundle";

  # netboot-minimal pulls in the installation-device profile, which adds a
  # nixpkgs overlay; the test framework's shared read-only pkgs forbids that.
  node.pkgsReadOnly = false;

  nodes = {
    machine = {
      virtualisation.vlans = [ ];
      virtualisation.memorySize = 6 * 1024;
      # The bundle unpacks its closure into /nix/store, as it would on a real
      # rescue system. The test VM's store is the host's, read-only, so give it
      # a writable overlay and drop NixOS's read-only bind mount over it.
      virtualisation.writableStore = true;
      boot.nixStoreMountOpts = [
        "x-initrd.mount"
        "nodev"
        "nosuid"
      ];
    };

    target = {
      imports = [
        ../modules/format-options.nix
        ../extras/kexec-bundle.nix
      ];
      virtualisation.vlans = [ ];
    };
  };

  testScript =
    { nodes, ... }:
    ''
      machine.wait_for_unit("multi-user.target")

      # The bundle's documented hand-off: a public key at /ssh_pubkey on the old
      # system ends up as root's authorized_keys on the new one.
      machine.succeed("echo 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA0vm0parts0test0key0000000000000000000 vm-parts-test' > /ssh_pubkey")
      machine.fail("test -e /root/.ssh/authorized_keys")
      machine.succeed("touch /run/before-kexec")

      machine.execute("${nodes.target.system.build.kexec_bundle} >&2 &", check_output=False)
      machine.connected = False
      machine.connect()
      machine.wait_for_unit("multi-user.target")

      # A fresh boot, into the bundled system...
      machine.fail("test -e /run/before-kexec")
      machine.succeed('[ "$(hostname)" = "${nodes.target.networking.hostName}" ]')

      # ...with the key installed by the initrd unit, readable only by root.
      machine.succeed("grep -q vm-parts-test /root/.ssh/authorized_keys")
      machine.succeed('[ "$(stat -c %a /root/.ssh/authorized_keys)" = 600 ]')
      machine.succeed('[ "$(stat -c %a /root/.ssh)" = 700 ]')

      machine.shutdown()
    '';
}
