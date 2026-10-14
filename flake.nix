{
  description = "AirDrop radio backend for omdrop on Wi-Fi cards without Apple's Broadcom firmware";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      forAll = f: nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ] (s: f nixpkgs.legacyPackages.${s});
    in
    {
      packages = forAll (pkgs: {
        default = pkgs.callPackage ./nix/package.nix { };
      });

      # Built from the system's nixpkgs, not this flake's: nmcli has to match
      # the NetworkManager the system runs (nix/module.nix).
      nixosModules.default = ./nix/module.nix;
    };
}
