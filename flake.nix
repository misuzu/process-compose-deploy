{
  outputs = inputs: {
    nixosModules.default = ./module.nix;
    nixosModule = inputs.self.nixosModules.default;
  };
}
