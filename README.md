# NixOS Unattended Installer

Create unattended NixOS installer. Disko configuration is required. And flakes I guess.

It's quite trivial, but effective. It creates a new NixOS system configuration based on installer ISO, and adds a systemd service that runs disko to format disks, and nixos-install to install target NixOS system.

## Usage

There's a wrapper function located at `nixos-unattended-installer.lib.diskoInstallerWrapper` which takes two arguments: `target` and `config`.

`target` needs to be a NixOS configuration attribute set, same as what's returned by `nixpkgs.lib.nixosSystem`. Required.

`config` is an attribute set with following optional arguments.

`config.system` is architecture and platform, defaults to target system.

`config.showProgress` is a bool that causes a TTY to be spawned and switched to that shows installation progress.

If `config.flake` is set to a flake path, it will be both built and installed on target. Might be preferable to get a latest version of said flake, or if target machine is a better fit for build and installation.

Some more arguments are accepted, and you can find out about them in [`./disko-install-module.nix`](./disko-install-module.nix).

The wrapper function just creates a new NixOS configuration, based on installer ISO, with above mentioned module configured.

## Example flake.nix

Generate ISO by `nix build .#nixosConfigurations.example-installer.config.system.build.isoImage`.

```nix
{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, disko }: {
    nixosConfigurations = {
      example-installer = self.lib.diskoInstallerWrapper self.nixosConfigurations.example-machine { };

      example-machine = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          ({ config, modulesPath, ... }: {
            boot.loader.grub.devices = [ config.disko.devices.disk.sda.device ];
            disko.devices.disk.sda ={
              device = "/dev/sda";
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
```

More examples in [`./flake.nix`](./flake.nix).
