{
  description = "pKVM-IA development environment";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      mkKernel = import ./nix/kernel-package.nix;
    in
    {
      packages.${system} = {
        linux-pkvm-host = mkKernel {
          inherit pkgs;
          isGuest = false;
        };

        linux-pkvm-guest = mkKernel {
          inherit pkgs;
          isGuest = true;
        };

        default = self.packages.${system}.linux-pkvm-host;
      };

      devShells.${system}.default = import ./shell.nix { inherit pkgs; };
    };
}
