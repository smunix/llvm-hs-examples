{
  description = "Examples using the llvm-hs library";
  inputs = {
    np.url = "github:nixos/nixpkgs?ref=haskell-updates";
    fu.url = "github:numtide/flake-utils?ref=master";
    nf.url = "github:numtide/nix-filter?ref=master";
    hls.url = "github:haskell/haskell-language-server?ref=master";
    smx.url = "github:smunix/llvm-hs?ref=pre.llvm-12";
  };
  outputs = { self, np, fu, nf, hls, smx }:
    with fu.lib;
    with np.lib;
    with builtins;
    eachSystem [ "x86_64-linux" ] (system:
      let
        version = ghc:
          with np.lib;
          "${ghc}-${substring 0 8 self.lastModifiedDate}.${
            self.shortRev or "dirty"
          }";
        config = { };
        mkOverlay = ghc: final: _:
          with final;
          let
            hsPkgs = haskell.packages."ghc${ghc}".extend (final: _:
              with final;
              with haskell.lib;
              let
                smxPkg = ghc: name:
                  let pkgPath = "ghc${ghc}/${name}";
                  in smx.packages.${system}.${pkgPath};
              in rec {
                llvm-hs = smxPkg ghc "llvm-hs";
                llvm-hs-pure = smxPkg ghc "llvm-hs-pure";
                llvm-hs-pretty = smxPkg ghc "llvm-hs-pretty";
                llvm-hs-combinators = smxPkg ghc "llvm-hs-combinators";
              });
          in {
            "${ghc}" = with hsPkgs;
              with haskell.lib; rec {
                inherit (hsPkgs)
                  llvm-hs llvm-hs-pure llvm-hs-pretty llvm-hs-combinators;
                llvm-hs-examples = (callCabal2nix "llvm-hs-examples"
                  (with nf.lib;
                    filter {
                      root = ./.;
                      exclude = [ "stack.yaml" "examples.cabal" ];
                    }) { inherit llvm-hs llvm-hs-pure; }).overrideAttrs
                  (o: { version = "${o.version}-${version ghc}"; });
              };
          };
        mkOverlays = ghcs: [ hls.overlay ] ++ (map mkOverlay ghcs);
        withGHC = ghcs:
          let
            pkgs = (import np {
              inherit system config;
              overlays = (mkOverlays ghcs);
            });
          in with pkgs;
          with builtins; rec {
            inherit (pkgs) overlays;
            packages = flattenTree (recurseIntoAttrs (with lib.lists;
              with lib.attrsets;
              foldr
              (ghc: s: { "${ghc}" = recurseIntoAttrs pkgs."${ghc}"; } // s) { }
              ghcs));
            defaultPackage = packages."${head ghcs}/llvm-hs-examples";
            apps = with lib.lists;
              with lib.attrsets;
              foldr (ghc: s:
                {
                  "basic-${ghc}" = mkApp {
                    drv = packages."${ghc}/llvm-hs-examples";
                    exePath = "/bin/basic";
                  };
                  "orc-${ghc}" = mkApp {
                    drv = packages."${ghc}/llvm-hs-examples";
                    exePath = "/bin/orc";
                  };
                  "irbuilder-${ghc}" = mkApp {
                    drv = packages."${ghc}/llvm-hs-examples";
                    exePath = "/bin/irbuilder";
                  };
                  "arith-${ghc}" = mkApp {
                    drv = packages."${ghc}/llvm-hs-examples";
                    exePath = "/bin/arith";
                  };
                } // s) { } ghcs;
            defaultApp = apps."basic-${head ghcs}";
            devShell = with haskell.packages."ghc${head ghcs}";
              shellFor {
                packages = _: [ defaultPackage ];
                buildInputs = [
                  cabal-install
                  ghc
                  haskell-language-server
                  hpack
                  llvmPackages_12.llvm
                ];
              };
          };

      in (withGHC [ "902" "8107" ]));
}
