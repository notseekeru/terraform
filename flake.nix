{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-infisical.url = "https://channels.nixos.org/nixos-unstable/nixexprs.tar.xz";
  };

  outputs = { self, nixpkgs, nixpkgs-infisical }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);
    in
    {
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
          infisical = nixpkgs-infisical.legacyPackages.${system}.infisical;
        in
        {
          default = pkgs.mkShell {
            buildInputs = [
              infisical
            ] ++ (with pkgs; [
              kubectl
              terraform
              argocd
              aws-nuke
            ]);
          };
        });
    };
}
