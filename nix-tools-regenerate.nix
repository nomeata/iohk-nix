# A script for generating the nix haskell package set based on stackage,
# using the common convention for repo layout.

{ lib, stdenv, path, writeScript, nix-tools, coreutils, gawk
, nix, nix-prefetch-scripts }:

let
  deps = [ nix-tools coreutils gawk nix nix-prefetch-scripts ];

in
  writeScript "nix-tools-regenerate" ''
    #!${stdenv.shell}
    #
    # Haskell package set regeneration script.
    #
    # stack-to-nix will transform the stack.yaml file into something
    # nix can understand.
    #

    set -euo pipefail
    # See https://github.com/NixOS/nixpkgs/pull/47676 for why we add /usr/bin to
    # the PATH on darwin. The security-tool in nixpkgs is broken on macOS Mojave.
    export PATH=${(lib.makeBinPath deps) + lib.optionalString stdenv.isDarwin ":/usr/bin"}
    export NIX_PATH=nixpkgs=${path}

    dest=nix/.stack-pkgs.nix

    mkdir -p "$(dirname "$dest")"

    function cleanup {
      rm -f "$dest.new"
    }
    trap cleanup EXIT

    stack-to-nix -o nix stack.yaml > "$dest.new"
    mv "$dest.new" "$dest"

    echo "Wrote $dest"
  ''
