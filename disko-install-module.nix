{ config, lib, pkgs, ... }:
let
  cfg = config.unattendedInstaller;
in
{
  options.unattendedInstaller = {
    # Quite necessary that this is disabled by default. Otherwise this project could be renamed "unintended-reinstaller" ;)
    enable = lib.mkEnableOption "Unattended installation service, for installing NixOS with disko on boot.";
    target = lib.mkOption {
      type = lib.types.attrs;
      description = "A NixOS system attrset (nixosSystem)";
      example = "self.nixosConfigurations.<machine>";
    };
    showProgress = lib.mkOption {
      type = lib.types.bool;
      description = "Show installation progress.";
      default = true;
    };
    flake = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      description = "Flake uri to install, which avoids full target toplevel from being included in store on installer. Needs to be in the format `/path/to/flake#machine-name`.";
      example = "github:some/where#machine";
      default = null;
    };
    nixosInstallFlags = lib.mkOption {
      type = lib.types.str;
      description = "Flags (command line arguments) given to the nixos-install command.";
      default = "--no-channel-copy";
    };
    errorAction = lib.mkOption {
      type = lib.types.str;
      description = "Command(s) to run on installation failure.";
      default = "echo Installation failed!";
    };
    successAction = lib.mkOption {
      type = lib.types.str;
      description = "Command(s) to run on installation success";
      default = "reboot";
    };
    waitForNetwork = lib.mkOption {
      type = lib.types.bool;
      description = "Wait for network before starting installation. Could be needed if using flake as installation source.";
      default = !builtins.isNull cfg.flake;
    };
    preDisko = lib.mkOption {
      type = lib.types.str;
      description = "Command(s) to run before disko runs.";
      default = "";
    };
    postDisko = lib.mkOption {
      type = lib.types.str;
      description = "Command(s) to run after disko runs.";
      default = "";
    };
    preInstall = lib.mkOption {
      type = lib.types.str;
      description = "Command(s) to run before nix-install.";
      default = "";
    };
    postInstall = lib.mkOption {
      type = lib.types.str;
      description = "Command(s) to run after nix-install.";
      default = "";
    };
  };
  config = lib.mkIf cfg.enable (lib.mkMerge [
    (lib.mkIf cfg.showProgress {
      systemd.services.unattended-installer-progress = {
        wantedBy = [ "multi-user.target" ];
        unitConfig = {
          After = [ "getty.target" ];
          Conflicts = [ "getty@tty8.service" ];
        };
        script = ''
          set -xeufo pipefail
          ${pkgs.coreutils}/bin/env -i ${pkgs.tmux}/bin/tmux start \; show -g
          ${pkgs.tmux}/bin/tmux new-session -d -s unattended-installer /bin/sh -lc 'journalctl -fo cat -u unattended-installer.service | ${pkgs.nix-output-monitor}/bin/nom --json; /bin/sh'
          ${pkgs.kbd}/bin/openvt -v --wait --login --console=8 --force --switch -- ${pkgs.coreutils}/bin/env -i TERM=linux ${pkgs.tmux}/bin/tmux attach-session -t unattended-installer
        '';
      };
    })
    ({
      systemd.services.unattended-installer = {
        wantedBy = [ (if cfg.waitForNetwork then "network-online.target" else "multi-user.target") ];
        path = [
          pkgs.nix # Dependency of nixos-install
          # Dependencies of disko/disk-deactivate
          pkgs.gawk
          pkgs.zfs
        ];
        script = let
          a = builtins.elemAt (builtins.split "^([^#]*)#(.*)$" cfg.flake) 1;
          flake-uri-for-nix-build = "${builtins.elemAt a 0}#nixosConfigurations.${builtins.elemAt a 1}.config.system.build.toplevel";
        in ''
          set -xeufo pipefail
          trap ${lib.strings.escapeShellArg cfg.errorAction} EXIT
          ${cfg.preDisko}
          echo Wiping and formatting disks, and then mounting to /mnt, using disko
          ${cfg.target.config.system.build.diskoScript}
          ${cfg.postDisko}

          ${cfg.preInstall}
          echo Building and installing NixOS
          ${if (builtins.isNull cfg.flake) then ''
              # Regular install from store
              ${pkgs.nixos-install-tools}/bin/nixos-install --system ${cfg.target.config.system.build.toplevel} ${cfg.nixosInstallFlags}
          '' else ''
              # Flake install
              ${if cfg.showProgress then ''
                ${pkgs.nix}/bin/nix build --extra-experimental-features 'nix-command flakes' -v -L --show-trace --no-link --log-format internal-json ${flake-uri-for-nix-build}
              '' else ""}
              ${pkgs.nixos-install-tools}/bin/nixos-install --flake ${cfg.flake} ${cfg.nixosInstallFlags}
          ''}
          ${cfg.postInstall}
          trap - EXIT
          echo Installation seems successful. Precautionary unmount
          ${pkgs.util-linux}/bin/umount -lfR /mnt || true
          # ZFS is sometimes messy with networking.hostId. Exporting all pools should help.
          ${pkgs.zfs}/bin/zpool export -af || true
          echo Now running success action
          ${cfg.successAction}
        '';
        };
      })
    ]);
}
