{
  description = "flake for Rex4L";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    zig-overlay.url = "github:mitchellh/zig-overlay";
    zig2nix = {
      url = "github:Cloudef/zig2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      flake-utils,
      zig-overlay,
      zig2nix,
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ zig-overlay.overlays.default ];
        };

        zig = pkgs.zigpkgs."0.17.0";
        zls = pkgs.zls_0_17;
        zigEnv = zig2nix.outputs.zig-env.${system} {
          inherit nixpkgs zig zls;
        };
        zigDeps = pkgs.callPackage ./build.zig.zon.nix {
          inherit zig;
          name = "rex4l-zig-dependencies";
        };
      in
      {
        packages.default = pkgs.stdenv.mkDerivation {
          pname = "rex4l";
          version = "0.0.0";
          src = pkgs.lib.cleanSource ./.;

          nativeBuildInputs = [
            zig
            pkgs.pkg-config
          ];
          buildInputs = [ pkgs.gtk4 ];
          dontConfigure = true;

          preBuild = ''
            export ZIG_GLOBAL_CACHE_DIR=$TMPDIR/zig-cache
            export ZIG_LOCAL_CACHE_DIR=$TMPDIR/zig-local-cache
            mkdir -p "$ZIG_GLOBAL_CACHE_DIR/p"
            for dep in ${zigDeps}/*; do
              ln -s "$dep" "$ZIG_GLOBAL_CACHE_DIR/p/$(basename "$dep")"
            done
          '';

          buildPhase = ''
            runHook preBuild
            zig build -Doptimize=ReleaseSafe --prefix "$out"
            runHook postBuild
          '';

          dontInstall = true;
          meta = {
            description = "Linux client for the Rex multiplexer";
            platforms = pkgs.lib.platforms.linux;
            mainProgram = "Rex4L";
          };
        };
        devShells.default = pkgs.mkShell {
          packages =
            with pkgs;
            [
              zig
              zls
              pkg-config
              zigEnv.zig2nix
            ]
            ++ lib.optionals stdenv.hostPlatform.isLinux [
              gtk4
            ];
        };
      }
    );
}
