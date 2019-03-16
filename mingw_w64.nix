# Cross compilation logic.
# Returns override fields for use with nix-tools.
{ stdenv
, lib
, writeScriptBin
, wine
, mingw_w64_pthreads
, iserv-proxy
, remote-iserv
, gmp
# extra libraries. Their dlls are copied
# when tests are run.
, extra-test-libs ? []
}:
let

  wineIservWrapper = writeScriptBin "iserv-wrapper" ''
    #!${stdenv.shell}
    set -euo pipefail
    # unset the configureFlags.
    # configure should have run already
    # without restting it, wine might fail
    # due to a too large environment.
    unset configureFlags
    PORT=$((5000 + $RANDOM % 5000))
    (>&2 echo "---> Starting remote-iserv on port $PORT")
    WINEDLLOVERRIDES="winemac.drv=d" WINEDEBUG=-all+error WINEPREFIX=$TMP ${wine}/bin/wine64 ${remote-iserv}/bin/remote-iserv.exe tmp $PORT &
    (>&2 echo "---| remote-iserv should have started on $PORT")
    RISERV_PID="$!"
    ${iserv-proxy}/bin/iserv-proxy $@ 127.0.0.1 "$PORT"
    (>&2 echo "---> killing remote-iserv...")
    kill $RISERV_PID
  '';
  ################################################################################
  # Build logic (TH support via remote iserv via wine)
  #
  setupBuildFlags = map (opt: "--ghc-option=" + opt) [
    "-fexternal-interpreter"
    "-pgmi" "${wineIservWrapper}"
    # TODO: this should be automatically injected based on the extraLibrary.
    "-L${mingw_w64_pthreads}/lib"
    "-L${mingw_w64_pthreads}/bin"
    "-L${gmp}/lib"
  ];

  ################################################################################
  # Test logic via wine
  #
  wineTestWrapper = writeScriptBin "test-wrapper" ''
    #!${stdenv.shell}
    set -euo pipefail
    WINEDLLOVERRIDES="winemac.drv=d" WINEDEBUG=-all+error LC_ALL=en_US.UTF-8 WINEPREFIX=$TMP ${wine}/bin/wine64 $@*
  '';
  setupTestFlags = [ "--test-wrapper ${wineTestWrapper}/bin/test-wrapper" ];
  preCheck = ''
    echo "================================================================================"
    echo "RUNNING TESTS for $name via wine64"
    echo "================================================================================"
    echo "Copying extra test libraries ..."
    for p in ${lib.concatStringsSep " "extra-test-libs}; do
      find "$p" -iname '*.dll' -exec cp {} . \;
    done
    # copy all .dlls into the local directory.
    # we ask ghc-pkg for *all* dynamic-library-dirs and then iterate over the unique set
    # to copy over dlls as needed.
    echo "Copying library dependencies..."
    for libdir in $(x86_64-pc-mingw32-ghc-pkg --package-db=$packageConfDir field "*" dynamic-library-dirs --simple-output|xargs|sed 's/ /\n/g'|sort -u); do
      if [ -d "$libdir" ]; then
        find "$libdir" -iname '*.dll' -exec cp {} . \;
      fi
    done
  '';
  postCheck = ''
    echo "================================================================================"
    echo "END RUNNING TESTS"
    echo "================================================================================"
  '';

in { inherit preCheck postCheck setupBuildFlags setupTestFlags; }
