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

    # nixpkgs' netboot chain already defines this, so overriding rather than
    # adding is required -- without mkForce the module system reports
    # `kexec_tarball' as defined in multiple locations.
    kexec_tarball = lib.mkForce (
      pkgs.callPackage "${toString modulesPath}/../lib/make-system-tarball.nix" {
        storeContents = [
          {
            object = config.system.build.kexec_script;
            symlink = "/kexec_nixos";
          }
        ];
        contents = [ ];
      }
    );

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
  networking.hostName = lib.mkDefault "kexec";

  # The bundle's whole point is SSH takeover: kexec_script above injects an
  # `authorized_keys` into the initrd, and this copies it into the booted system.
  #
  # `boot.initrd.postMountCommands` is a scripted-stage-1 API and asserts out
  # under systemd stage 1, so pin this format to scripted stage 1. That is what
  # the nixos-generators original ran under, which keeps the port faithful rather
  # than shipping an untested systemd-initrd translation. Porting it to
  # `boot.initrd.systemd.services` (and /sysroot rather than /mnt-root) is
  # tracked separately.
  boot.initrd.systemd.enable = lib.mkForce false;

  boot.initrd.postMountCommands = ''
    mkdir -p /mnt-root/root/.ssh/
    cp /authorized_keys /mnt-root/root/.ssh/
  '';

  format.attr = "kexec_bundle";
  format.filePath = null;
}
