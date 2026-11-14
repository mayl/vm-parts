# Ported from nix-community/nixos-generators (MIT), formats/kexec.nix and
# formats/kexec-bundle.nix, rebased onto nixpkgs' netboot-minimal module.
#
# nixpkgs does have a `kexec` image variant, but it is the netboot payload
# (kernel + initrd + a script). This format is the other half of what
# nixos-generators offered: a single self-extracting executable that unpacks
# itself into / and kexecs into the new system. Handy for taking over a rescue
# environment over SSH.
#
# `$out` here is the bundle itself rather than a directory containing it, so
# `format.filePath` stays null and `result` is already the executable.
{
  config,
  pkgs,
  lib,
  modulesPath,
  ...
}:
{
  imports = [ "${toString modulesPath}/installer/netboot/netboot-minimal.nix" ];

  system.build = rec {
    kexecImage = pkgs.runCommand "kexec-image" { buildInputs = [ pkgs.nukeReferences ]; } ''
      mkdir $out
      cp ${config.system.build.kernel}/${config.system.boot.loader.kernelFile} $out/kernel
      cp ${config.system.build.netbootRamdisk}/initrd $out/initrd
      echo "init=${builtins.unsafeDiscardStringContext config.system.build.toplevel}/init ${toString config.boot.kernelParams}" > $out/cmdline
      nuke-refs $out/kernel
    '';

    kexec_script = pkgs.writeTextFile {
      executable = true;
      name = "kexec-nixos";
      text = ''
        #!${pkgs.stdenv.shell}
        export PATH=${pkgs.kexec-tools}/bin:${pkgs.cpio}/bin:$PATH
        set -x
        set -e
        cd $(mktemp -d)
        pwd
        mkdir initrd
        pushd initrd
        if [ -e /ssh_pubkey ]; then
          cat /ssh_pubkey >> authorized_keys
        fi
        find -type f | cpio -o -H newc | gzip -9 > ../extra.gz
        popd
        cat ${kexecImage}/initrd extra.gz > final.gz

        kexec -l ${kexecImage}/kernel --initrd=final.gz --append="init=${builtins.unsafeDiscardStringContext config.system.build.toplevel}/init ${toString config.boot.kernelParams}"
        sync
        echo "executing kernel, filesystems will be improperly umounted"
        kexec -e
      '';
    };

    kexec_tarball = pkgs.callPackage "${toString modulesPath}/../lib/make-system-tarball.nix" {
      storeContents = [
        {
          object = config.system.build.kexec_script;
          symlink = "/kexec_nixos";
        }
      ];
      contents = [ ];
    };

    kexec_tarball_self_extract_script = pkgs.writeTextFile {
      executable = true;
      name = "kexec-nixos";
      text = ''
        #!/bin/sh
        set -eu
        ARCHIVE=`awk '/^__ARCHIVE_BELOW__/ { print NR + 1; exit 0; }' $0`

        tail -n+$ARCHIVE $0 | tar xJ -C /
        /kexec_nixos

        exit 1

        __ARCHIVE_BELOW__
      '';
    };

    kexec_bundle = pkgs.runCommand "kexec_bundle" { } ''
      cat \
        ${kexec_tarball_self_extract_script} \
        ${config.system.build.kexec_tarball}/tarball/nixos-system-${config.system.build.kexec_tarball.system}.tar.xz \
        > $out
      chmod +x $out
    '';
  };

  boot.loader.grub.enable = lib.mkForce false;
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.kernelParams = [
    "console=ttyS0,115200" # allows certain forms of remote access, if the hardware is set up right
    "panic=30"
    "boot.panic_on_fail" # reboot the machine upon fatal boot issues
  ];
  systemd.services.sshd.wantedBy = lib.mkForce [ "multi-user.target" ];
  # Weaker than `mkDefault`, so that a machine that sets its own hostname at
  # `mkDefault` (as the NixOS test framework does) wins instead of conflicting.
  networking.hostName = lib.mkOverride 1200 "kexec";

  # netboot-minimal enables ZFS support, and nixpkgs warns on every evaluation
  # until `forceImportRoot` is set explicitly. Root here is a tmpfs, so there is
  # no ZFS root to force-import; `false` is also the upcoming nixpkgs default.
  boot.zfs.forceImportRoot = lib.mkDefault false;

  # The bundle's whole point is SSH takeover. kexec_script above appends a
  # second cpio archive holding `/authorized_keys` (taken from the old system's
  # /ssh_pubkey) to the initrd; the kernel unpacks it over the initramfs root.
  # This unit then copies it into the new system before switching root.
  #
  # nixos-generators did this with `boot.initrd.postMountCommands`, a scripted
  # stage 1 hook. Scripted stage 1 was removed from nixpkgs in 26.11, so this is
  # the systemd stage 1 equivalent: `/sysroot` is the new root (scripted stage 1
  # called it /mnt-root), and `initrd-fs.target` is the point at which it and
  # everything under it is mounted.
  boot.initrd.systemd.services.kexec-authorized-keys = {
    description = "Install the kexec bundle's SSH authorized_keys for root";
    wantedBy = [ "initrd.target" ];
    after = [ "initrd-fs.target" ];
    before = [ "initrd.target" ];
    unitConfig = {
      DefaultDependencies = false;
      ConditionPathExists = "/authorized_keys";
    };
    serviceConfig.Type = "oneshot";
    script = ''
      mkdir -p -m 0700 /sysroot/root/.ssh
      cp /authorized_keys /sysroot/root/.ssh/authorized_keys
      chmod 0600 /sysroot/root/.ssh/authorized_keys
    '';
  };

  format.attr = "kexec_bundle";
  format.filePath = null;
}
