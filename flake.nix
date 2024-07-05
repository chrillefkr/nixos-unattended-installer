{
  description = "NixOS automatic unattended installer using disko";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable"; # Only used for tests
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko }@args: {
    nixosModules.diskoInstaller = import ./disko-install-module.nix;
    nixosModules.default = self.nixosModules.diskoInstaller;

    lib.diskoInstallerWrapper = target: ({
      system ? null # Defaults to target system
    , config ? null # Additional configuration for installation system
    , ... }@args: target.lib.nixosSystem {
      system = if (builtins.isNull system) then target.pkgs.system else system;
      modules = [
        self.nixosModules.diskoInstaller
        ({ modulesPath, lib, ... }: {
          imports = [
            "${modulesPath}/installer/cd-dvd/installation-cd-minimal.nix"
          ];
          unattendedInstaller = (builtins.removeAttrs (args // { inherit target; enable = lib.mkDefault true; }) [ "system" "config" ]);
          # Prettier output:
          nix.settings = lib.mkIf (args ? flake && !builtins.isNull args.flake) {
            extra-experimental-features = [ "nix-command" "flakes" ];
            accept-flake-config = true;
          };
          boot.kernelParams = [ "quiet" "systemd.show_status=no" ];
        })
      ] ++ (if builtins.isNull config then [] else [ config ]);
    });



    # The rest of this flake is just examples and tests

    nixosConfigurations = {

      # nix run .\#nixosConfigurations._example-installer.config.system.build.vm
      _example-installer = self.lib.diskoInstallerWrapper self.nixosConfigurations._test-machine {
        successAction = "poweroff"; # Poweroff instead of reboot
        config = ({ config, lib, modulesPath, ... }: {
          imports = [
            "${modulesPath}/profiles/headless.nix"
          ];
          system.name = "test-unattended-installer";
          networking.hostName = config.system.name;
          virtualisation.vmVariant = {
            virtualisation.memorySize = 4096; # A bit more memory is usually needed when building on target (i.e. using flake)
            virtualisation.diskImage = null; # Disable persistant storage
            virtualisation.emptyDiskImages = [ (1024 * 5) ]; # Add one 5 GiB disk to install onto
          };
          # nix run .\#nixosConfigurations._example-installer.config.specialisation.with-flake.configuration.system.build.vm
          specialisation.with-flake.configuration = {
            unattendedInstaller.flake = "${self}#_test-machine";
          };
        });
      };

      _test-machine = nixpkgs.lib.nixosSystem {
        #system = "x86_64-linux";
        system = "aarch64-linux";
        modules = [
          disko.nixosModules.disko
          ({ config, modulesPath, ... }: {
            imports = [
              # Try to keep test machine small
              "${modulesPath}/profiles/headless.nix"
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
      };
    };
  };
}
