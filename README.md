# process-compose-deploy

### Set up

```nix
inputs.process-compose-deploy.url = "github:misuzu/process-compose-deploy";

# for NixOS
imports = [ inputs.process-compose-deploy.nixosModules.default ];

# for nix-darwin
imports = [ inputs.process-compose-deploy.darwinModules.default ];

services.process-compose-deploy.default.enable = true;
```

### Attach default instance

```
sudo process-compose-adm-default attach
```

### Deploy simple example

```
sudo process-compose-deploy-default $(nix build --print-out-paths --no-link github:misuzu/process-compose-deploy?dir=example/simple) -v
```

### Deploy `microvm.nix` instance

```
sudo process-compose-deploy-default $(nix build --print-out-paths --no-link github:misuzu/process-compose-deploy?dir=example/microvm) -v
```

### Deploy `services-flake` service

```
sudo process-compose-deploy-default $(nix build --print-out-paths --no-link github:juspay/services-flake?dir=example/simple) -v
```

### Remote deployments

```
# build the flake
nix build github:juspay/services-flake?dir=example/simple
# push the build result to cache (e.g. attic)
nix shell nixpkgs#attic-client -c attic push mycache $(readlink -f ./result)
# deploy
ssh myuser@myhost sudo process-compose-deploy-default $(readlink -f ./result)
```

## Related projects

- [`process-compose-flake`](https://github.com/juspay/services-flake): A `flake-parts` module to spin up processes for development by leveraging `process-compose`.
- [`services-flake`](https://github.com/juspay/services-flake): NixOS-like services built on top of `process-compose-flake`.
- [`microvm.nix`](https://github.com/astro/microvm.nix): NixOS MicroVMs.
- [`attic`](https://github.com/zhaofengli/attic): Multi-tenant Nix Binary Cache.
