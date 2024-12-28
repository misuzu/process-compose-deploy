# https://github.com/astro/microvm.nix/blob/main/flake-template/flake.nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  inputs.process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";

  inputs.microvm.url = "github:astro/microvm.nix";
  inputs.microvm.inputs.nixpkgs.follows = "nixpkgs";

  outputs =
    inputs:
    let
      system = "x86_64-linux";
    in
    {
      nixosConfigurations = {
        my-microvm = inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          modules = [
            inputs.microvm.nixosModules.microvm
            {
              networking.hostName = "my-microvm";
              users.users.root.password = "";
              microvm = {
                volumes = [
                  {
                    mountPoint = "/var";
                    image = "var.img";
                    size = 256;
                  }
                ];
                shares = [
                  {
                    # use proto = "virtiofs" for MicroVMs that are started by systemd
                    proto = "9p";
                    tag = "ro-store";
                    # a host's /nix/store will be picked up so that no
                    # squashfs/erofs will be built for it.
                    source = "/nix/store";
                    mountPoint = "/nix/.ro-store";
                  }
                ];

                # "qemu" has 9p built-in!
                hypervisor = "qemu";
                socket = "control.socket";
              };
            }
          ];
        };
      };
      packages.${system} = {
        my-microvm = inputs.self.nixosConfigurations.my-microvm.config.microvm.declaredRunner;
        process-compose-my-microvm =
          (import inputs.process-compose-flake.lib {
            pkgs = inputs.nixpkgs.legacyPackages.${system};
          }).makeProcessCompose
            {
              modules = [
                {
                  settings.processes.my-microvm.command = inputs.self.packages.${system}.my-microvm;
                }
              ];
            };
        default = inputs.self.packages.${system}.process-compose-my-microvm;
      };
    };
}