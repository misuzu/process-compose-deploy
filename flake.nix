{
  outputs = inputs: {
    darwinModules.default = ./darwin-module.nix;
    nixosModules.default = ./nixos-module.nix;
  };
}
