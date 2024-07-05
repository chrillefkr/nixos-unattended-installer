{ self, nixpkgs, disko, ... }:
let
  rpi-bootloader = { config, pkgs, lib, ... }:
  let
    config-txt = pkgs.writeText "config.txt" ''
      [pi3]
      kernel=Tow-Boot.noenv.rpi3.bin

      [pi4]
      kernel=Tow-Boot.noenv.rpi4.bin
      enable_gic=1
      armstub=armstub8-gic.bin
      disable_overscan=1

      [all]
      arm_64bit=1
      enable_uart=1
      avoid_warnings=1

      over_voltage=6
      arm_freq=2000
      gpu_freq=750
    '';
    tow-boot-src = builtins.fetchGit {
      url = "https://github.com/Tow-Boot/Tow-Boot.git";
      name = "Tow-Boot";
      rev = "3436997d2904225d75acf2e9c76c58f78ac4bf57";
    };
    #tow-boot-builder = import "${tow-boot-src}/default.nix";
    #tow-boot-rpi-builder = import "${tow-boot-src}/boards/raspberryPi-aarch64/default.nix";
    evalConfig = import "${toString pkgs.path}/nixos/lib/eval-config.nix";
    fromNixpkgs = map (module: "${toString pkgs.path}/nixos/modules/${module}");
    tow-boot-rpi-config = evalConfig {
      system = pkgs.system;
      baseModules = [
        #../../modules
        "${tow-boot-src}/modules"
      ] ++ (fromNixpkgs [
        "misc/assertions.nix"
        "misc/nixpkgs.nix"
      ]);
      modules = [
        "${tow-boot-src}/boards/raspberryPi-aarch64/default.nix"
      ];
    };
    tow-boot-rpi-4-firmware = evalConfig {
      system = pkgs.system;
      baseModules = [
        #../../modules
        "${tow-boot-src}/modules"
      ] ++ (fromNixpkgs [
        "misc/assertions.nix"
        "misc/nixpkgs.nix"
      ]);
      modules = [
        ({ config, lib, pkgs, ... }:
        {
          device.identifier = "raspberryPi-4";
          Tow-Boot.defconfig = "rpi_4_defconfig";
          hardware.soc = "generic-aarch64";
          device = {
            manufacturer = "Raspberry Pi";
            name = "Combined AArch64";
            #identifier = lib.mkDefault "raspberryPi-aarch64";
            productPageURL = "https://www.raspberrypi.com/products/";
            # This line of boards is YMMV.
            supportLevel = "experimental";
          };
        })
        #config.helpers.composeConfig {
        #  config = {
        #    device.identifier = "raspberryPi-4";
        #    Tow-Boot.defconfig = "rpi_4_defconfig";
        #  };
        #})
        #"${tow-boot-src}/boards/raspberryPi-aarch64/default.nix"
      ];
    };
    tow-boot-rpi = tow-boot-rpi-config.config.build.default.overrideAttrs ({ passthru ? {}, ... }: {
      passthru = passthru // {
        eval = tow-boot-rpi-config;
        inherit (tow-boot-rpi-config) config pkgs options;
        inherit (tow-boot-rpi-config.config) build;
      };
    });

    installTowBootScript = pkgs.writeScript "install-tow-boat.sh" ''
      set -eufo pipefail

      shopt -s nullglob

      target=/boot

      (
        pushd ${pkgs.raspberrypifw}/share/raspberrypi/boot &>/dev/null
        cp bcm2711-rpi-4-b.dtb "$target/"
        set +f
        cp bootcode.bin fixup*.dat start*.elf "$target/"
        set -f
        popd 2>&1 >/dev/null
      )

      cp -fr ${config-txt} $target/config.txt

      cp -fr ${pkgs.raspberrypi-armstubs}/armstub8-gic.bin $target/armstub8-gic.bin

      cp -fr ${tow-boot-rpi}/binaries/Tow-Boot.noenv.rpi{3,4}.bin $target/
    '';
  in {
    boot.loader.efi.canTouchEfiVariables = false;

    # boot.loader.external = {
    #   enable = false;
    #   installHook = "${installTowBootScript}";
    # };
    boot.loader.grub.enable = false;
    #boot.loader.generic-extlinux-compatible.enable = true;
    boot.loader.generic-extlinux-compatible.enable = false;
    boot.loader.systemd-boot.enable = true;
    boot.loader.systemd-boot.extraInstallCommands = ''
      ${installTowBootScript}
    '';
    # system.build.installBootLoader = lib.mkForce (pkgs.writeScript "install-boot-loader.sh" ''
    #   set -xeufo pipefail
    #   toplevel="$1"
    #   ${installTowBootScript} "$toplevel"
    #   #''${config.boot.loader.generic-extlinux-compatible.populateCmd} -c "$toplevel"
    # '');
  };
in
nixpkgs.lib.nixosSystem {
  system = "aarch64-linux";
  modules = [
    disko.nixosModules.disko
    ({ config, modulesPath, ... }: {
      imports = [
        # Try to keep test machine small
        rpi-bootloader
        #"${modulesPath}/profiles/headless.nix"
        "${modulesPath}/profiles/minimal.nix"
      ];
      boot.loader.grub.devices = [ config.disko.devices.disk.vda.device ];
      disko.devices.disk.vda ={
        device = "/dev/vda";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              type = "EF00";
              size = "500M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            root = {
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
          };
        };
      };
    })
  ];
