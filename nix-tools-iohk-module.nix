# This file contains patches across haskell packages that
# amend the packages to be cross-compilable to windows,
# and potentially later other targets.
#
# The module is supposed to be used as part of the pkgSet's
# `modules` setion:
# Example:
#    modules = [
#      haskell.ghcHackagePatches.${(stack-pkgs.extras hackage).compiler.nix-name}
#      iohk-module
#    ];
#
commonLib:
# we need nixpkgs as this will be the properly configured one
# the one that gives us the right host and target platforms.
{ nixpkgs
# The packages which need TH, for these we will setup the
# template haskell runner (via wine for windows) and pass
# -fexternal-interpreter to ghc.
, th-packages ? []
}:
{ pkgs, buildModules, config, lib, ... }:
let
  withTH = import ./mingw_w64.nix {
    inherit (commonLib.pkgs) stdenv lib writeScriptBin;
    wine = pkgs.buildPackages.winePackages.minimal;
    inherit (pkgs.windows) mingw_w64_pthreads;
    inherit (pkgs) gmp;
    # iserv-proxy needs to come from the buildPackages, as it needs to run on the
    # build host.
    inherit (config.hsPkgs.buildPackages.iserv-proxy.components.exes) iserv-proxy;
    # remote-iserv however needs to come from the regular packages as it has to
    # run on the target host.
    inherit (config.hsPkgs.remote-iserv.components.exes) remote-iserv;
    # we need to use openssl.bin here, because the .dll's are in the .bin expression.
    extra-test-libs = [ pkgs.rocksdb pkgs.openssl.bin ];
  } // {
    # we can perform testing of cross compiled test-suites by using wine.
    # Therfore let's enable doCrossCheck here!
    doCrossCheck = true;
  };
in {
  packages = {
    # This needs true, otherwise we miss most of the interesting
    # modules.
    ghci.flags.ghci = true;
    # I hope we can apply this globally.
    ghc.flags.ghci = true;

    # this needs to be true to expose module
    #  Message.Remote
    # as needed by libiserv.
    libiserv.flags.network = true;

    # libiserv has a bit too restrictive boundaries.
    # as such it won't build with newer network libraries.
    # to avoid that we use doExactConfig, which forces cabal
    # to forgoe its solver and just take the libraries it's
    # provided with.
    ghci.components.library.doExactConfig = true;
    libiserv.components.library.doExactConfig = true;
    # same for iserv-proxy
    iserv-proxy.components.exes.iserv-proxy.doExactConfig = true;
    remote-iserv.components.exes.remote-iserv.doExactConfig = true;

    # clock hasn't had a release since 2016(!) that is for three(3) years
    # now.
    clock.patches              = [ ({ version, revision }: (if version == "0.7.2" then ./patches/clock-0.7.2.patch else null)) ];
    # nix calles this package crypto
    cryptonite-openssl.patches = [ ({ version, revision }: if version == "0.7" then ./patches/cryptonite-openssl-0.7.patch else null) ];

    conduit.patches            = [ ./patches/conduit-1.3.0.2.patch ];
    streaming-commons.patches  = [ ./patches/streaming-commons-0.2.0.0.patch ];
    x509-system.patches        = [ ./patches/x509-system-1.6.6.patch ];
    file-embed-lzma.patches    = [ ./patches/file-embed-lzma-0.patch ];

    # Set all of these to [], as these form the
    # dependency graph of the libiserv, iserv-proxy, and iserv-remote
    # packages.  Subsequently we do not want the defaults that `withTH`
    # `-fexternal-interpreter` would install here.  That would ultimately
    # result in cyclic dependencies as it injects `remote-iserv` and
    # `iserv-proxy` as a dependency into every package.
    bytestring.setupBuildFlags = [];
    containers.setupBuildFlags = [];
    binary.setupBuildFlags = [];
    filepath.setupBuildFlags = [];
    time.setupBuildFlags = [];
    unix.setupBuildFlags = [];
    Win32.setupBuildFlags = [];
    libiserv.setupBuildFlags = [];
    iserv-proxy.setupBuildFlags = [];
    remote-iserv.setupBuildFlags = [];
    directory.setupBuildFlags = [];
    ghc-boot.setupBuildFlags = [];
    transformers.setupBuildFlags = [];
    ghci.setupBuildFlags = [];
    network.setupBuildFlags = [];

    # These are needed to ensure that hsc2hs
    # and happy are not build with TH support.
    # TODO: This should never be the case as
    # they should come from the buildPackages
    # and the withTH logic should only be enabled
    # when `isWindows`.  There must be some bug
    # in there...
    mtl.setupBuildFlags = [];
    process.setupBuildFlags = [];
    hsc2hs.setupBuildFlags = [];
    happy.setupBuildFlags = [];
  };
  } // lib.optionalAttrs nixpkgs.stdenv.hostPlatform.isWindows (withTH // {
  })
