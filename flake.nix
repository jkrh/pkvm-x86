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
    in
    {
      # Dummy default target
      packages.${system}.default = pkgs.emptyDirectory;

      devShells.${system}.default = import ./shell.nix { inherit pkgs; };
    };
}
