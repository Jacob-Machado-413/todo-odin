{
  description = "todo: a todo.txt-style CLI backed by a markdown file";

  inputs = {
    nixpkgs.url = "nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, flake-utils, nixpkgs, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};

        todo = pkgs.stdenv.mkDerivation {
          pname = "todo";
          version = self.shortRev or "dirty";
          src = ./.;

          nativeBuildInputs = [ pkgs.odin ];

          buildPhase = ''
            runHook preBuild
            odin build . -out:todo -o:speed
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            install -Dm755 todo -t $out/bin
            runHook postInstall
          '';

          meta.mainProgram = "todo";
        };

      in rec {
        packages.todo = todo;
        packages.default = todo;
        defaultPackage = todo;

        apps.todo = flake-utils.lib.mkApp { drv = packages.todo; };
        apps.default = apps.todo;
        defaultApp = apps.todo;

        # `nix develop` -> shell with odin + ols for working on this repo
        devShells.default = pkgs.mkShell { packages = [ pkgs.odin pkgs.ols ]; };
        devShell = devShells.default;
      });
}
