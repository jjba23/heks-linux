{
  description = "heks-linux: the Nix packages this configuration installs, pinned";

  inputs = {
    # The branch the registry's `flake:nixpkgs' followed before this flake
    # existed, named here so flake.lock pins it instead of a registry entry.
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    nix-jointhefreeworld = {
      url = "github:jjba23/nix-jointhefreeworld";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nix-jointhefreeworld }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      eachSystem = f: nixpkgs.lib.genAttrs systems f;
    in {
      legacyPackages = eachSystem (system: nixpkgs.legacyPackages.${system});

      packages = eachSystem (system: {
        heks-toon = nix-jointhefreeworld.packages.${system}.heks-toon;
        whelk = nix-jointhefreeworld.packages.${system}.whelk;
        lambdock = nix-jointhefreeworld.packages.${system}.lambdock;
      });
    };
}
