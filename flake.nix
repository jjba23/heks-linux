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
      # `maak install-nix-packages` installs `.#<attribute>`, and the set is
      # nixpkgs itself: whichever attribute the Guile list - or a machine's
      # nix-settings.scm - names resolves here, against the nixpkgs flake.lock
      # pins, instead of the floating `flake:nixpkgs` registry entry it came
      # from before.
      legacyPackages = eachSystem (system: nixpkgs.legacyPackages.${system});

      packages = eachSystem (system: {
        heks-toon = nix-jointhefreeworld.packages.${system}.heks-toon;
        # The desktop shell: the bar, the launcher, the notification daemon and
        # the lock screen this configuration uses instead of Waybar, Rofi, Mako
        # and swaylock. `maak install-nix-packages' installs it as `.#whelk'.
        whelk = nix-jointhefreeworld.packages.${system}.whelk;
      });
    };
}
