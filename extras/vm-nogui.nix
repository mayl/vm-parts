# Ported from nix-community/nixos-generators (MIT), formats/vm-nogui.nix.
#
# As ./vm.nix, but with the guest console on stdio instead of a graphical window.
{ pkgs, ... }:
let
  # Ask the terminal for its size and tell the guest tty about it, so that a
  # serial console resizes with the window it is running in.
  # https://unix.stackexchange.com/questions/16578/resizable-serial-console-window
  resize = pkgs.writeScriptBin "resize" ''
    if [ -e /dev/tty ]; then
      old=$(stty -g)
      stty raw -echo min 0 time 5
      printf '\033[18t' > /dev/tty
      IFS=';t' read -r _ rows cols _ < /dev/tty
      stty "$old"
      stty cols "$cols" rows "$rows"
    fi
  '';
in
{
  imports = [ ./vm.nix ];

  virtualisation.graphics = false;
  virtualisation.qemu.options = [ "-serial mon:stdio" ];

  environment.systemPackages = [ resize ];
  environment.loginShellInit = "${resize}/bin/resize";
}
