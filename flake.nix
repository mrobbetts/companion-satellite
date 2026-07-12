{
  description = "Bitfocus Companion Satellite - package and NixOS module";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { self, nixpkgs }:
    let
      # Upstream only supports x64 and arm64 Linux
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
    in
    {
      overlays.default = final: prev: {
        companion-satellite = final.callPackage ./pkgs/companion-satellite/package.nix { };
      };

      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ self.overlays.default ];
          };
        in
        {
          companion-satellite = pkgs.companion-satellite;
          default = pkgs.companion-satellite;
        }
      );

      nixosModules.companion-satellite =
        { pkgs, lib, ... }:
        {
          imports = [ ./modules/companion-satellite.nix ];
          # Default to the package built by this flake; override with
          # services.companion-satellite.package if you carry it in an overlay.
          services.companion-satellite.package = lib.mkDefault
            self.packages.${pkgs.stdenv.hostPlatform.system}.companion-satellite;
        };
      nixosModules.default = self.nixosModules.companion-satellite;
    };
}
