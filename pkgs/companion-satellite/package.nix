{
  stdenv,
  lib,
  fetchFromGitHub,
  fetchurl,
  runCommand,
  nodejs_24,
  python3,
  udev,
  yarn-berry_4,
  libusb1,
  makeWrapper,
  nix-update-script,
}:

let
  # Upstream requires node ^24.13 (engines in package.json). The same runtime
  # is also used for the surface-plugin child processes (see postPatch), which
  # declare 'node22' but are N-API based and run fine on newer node.
  nodejs = nodejs_24;
  yarn-berry = yarn-berry_4;

  # Builtin surface-plugin modules. Normally downloaded at build time by
  # tools/fetch_builtin_modules.mts; we fetch them with nix instead.
  # Keep in sync with assets/builtin-surface-modules.json in the source tree
  # when bumping `version` (the sha256 values below are copied verbatim from
  # that manifest - upstream publishes plain sha256 hex digests).
  builtinSurfaceModules = [
    {
      pname = "blackmagic-controller";
      src = fetchurl {
        url = "https://s4.bitfocus.io/developer-module-builds/surface/blackmagic-controller/v1.0.5-9dcda0321c79e296610ae4080aa7005eced222ac/blackmagic-controller-v1.0.5.tgz";
        sha256 = "2e719075e47c48122efb4cb61d88bc5c512533fe0de9e40cc7acb5f7bf1d3ea7";
      };
    }
    {
      pname = "contour-shuttle";
      src = fetchurl {
        url = "https://s4.bitfocus.io/developer-module-builds/surface/contour-shuttle/v1.0.2-8a12e6a96970700f0434a6d2193933a1ce42c8cd/contour-shuttle-v1.0.2.tgz";
        sha256 = "7e06a3e3ee661612858bc5ad8b24c5b7479eb6cc5dce6b9654ff9706f5d1de38";
      };
    }
    {
      pname = "elgato-stream-deck";
      src = fetchurl {
        url = "https://s4.bitfocus.io/developer-module-builds/surface/elgato-stream-deck/v1.4.3-70e2c01d15a0f58c52a8e80d7d6f4977f157d58e/elgato-stream-deck-v1.4.3.tgz";
        sha256 = "6d99d7be4c9f965cc7653009b47fe149822ff89e59398599c9c507773f6cac62";
      };
    }
    {
      pname = "idisplay-infinitton";
      src = fetchurl {
        url = "https://s4.bitfocus.io/developer-module-builds/surface/idisplay-infinitton/v1.0.1-e803b5ff8c4bb5c097873a12f90123652261fae1/idisplay-infinitton-v1.0.1.tgz";
        sha256 = "b9f6dedb9dbda553702d0ab648679d5a388cbe4cd0368d918ae1edfb8cf6cf05";
      };
    }
    {
      pname = "loupedeck";
      src = fetchurl {
        url = "https://s4.bitfocus.io/developer-module-builds/surface/loupedeck/v1.0.2-473ac7952ecb0d3f7f4e38d104932bb25cd7c8b8/loupedeck-v1.0.2.tgz";
        sha256 = "4142af8275f5c0afd7b5cf8c1d629be86bf257ceb4cb1502782603877a4907ff";
      };
    }
    {
      pname = "mirabox-stream-dock";
      src = fetchurl {
        url = "https://s4.bitfocus.io/developer-module-builds/surface/mirabox-stream-dock/v1.2.0-ae27380f73dc926f72391dc2e1ba7ca760bba57c/mirabox-stream-dock-v1.2.0.tgz";
        sha256 = "fa9305a2e8d919511443c2596af49c2a4ed5872e3ec1c721b7d4e1760e993860";
      };
    }
    {
      pname = "vec-footpedal";
      src = fetchurl {
        url = "https://s4.bitfocus.io/developer-module-builds/surface/vec-footpedal/v1.0.2-bcffd4c208c8647e667684f394f2c415928d9e50/vec-footpedal-v1.0.2.tgz";
        sha256 = "1d59311172af507e65638f13f805c9259de91be0f6eb78d58339ae97edb4218b";
      };
    }
    {
      pname = "xencelabs-quick-keys";
      src = fetchurl {
        url = "https://s4.bitfocus.io/developer-module-builds/surface/xencelabs-quick-keys/v1.0.3-a184938b03d3fc740f2cf2b23c1202863230463c/xencelabs-quick-keys-v1.0.3.tgz";
        sha256 = "83baf0898f17d38ec6da8ff055337ffc243d8cfd81fd078ca0aa61e3bdff9129";
      };
    }
    {
      pname = "xkeys";
      src = fetchurl {
        url = "https://s4.bitfocus.io/developer-module-builds/surface/xkeys/v1.0.2-876f00ee194faa57ec14468b7019bbaa516a9e6d/xkeys-v1.0.2.tgz";
        sha256 = "2d8243d166fdd21208b3c008899a2a2f1c4ab4c5a4a3daebc8f49db3d65809a7";
      };
    }
  ];

  builtinSurfaces = runCommand "companion-satellite-builtin-surfaces" { } (
    lib.concatMapStrings (m: ''
      mkdir -p "$out/${m.pname}"
      tar -xzf ${m.src} -C "$out/${m.pname}" --strip-components=1
    '') builtinSurfaceModules
  );

in

stdenv.mkDerivation rec {
  pname = "companion-satellite";
  version = "3.1.0";

  strictDeps = true;

  src = fetchFromGitHub {
    owner = "bitfocus";
    repo = "companion-satellite";
    tag = "v${version}";
    hash = "sha256-MiXOE0oBsKKEEcbRJjxZL8bFi36DgmZUUzuwoDmHF6o="; # 3.1.0
  };

  passthru.updateScript = nix-update-script { };

  postPatch = ''
    # postinstall runs husky (needs .git) and tools/dev_prepare.mts (downloads
    # node runtimes + builtin surface modules from the network). Nix handles
    # all of that, so neutralise it before the offline yarn install runs it.
    substituteInPlace package.json \
      --replace-fail '"postinstall": "husky && tsx ./tools/dev_prepare.mts",' '"postinstall": "true",'

    # Surface plugins run in child processes using a node binary that is
    # normally downloaded into node-runtimes/ next to the app. Always use the
    # nix node runtime instead. This is the "Pi headless" branch of
    # getNodeJsPath(); the access() check below it passes on the store path.
    substituteInPlace satellite/src/node-path.ts \
      --replace-fail \
        "join(import.meta.dirname, '../../node-runtimes', runtimeType, nodeBinExe)" \
        "'${lib.getExe nodejs}'"

    # In the packaged-electron layout (which the headless branch mimics),
    # node_modules sits inside satellite/. When built from source with yarn
    # workspaces, it is hoisted to the repository root - one level higher.
    substituteInPlace satellite/src/node-path.ts \
      --replace-fail \
        "join(import.meta.dirname, '../node_modules')" \
        "join(import.meta.dirname, '../../node_modules')"
  '';

  nativeBuildInputs = [
    nodejs
    yarn-berry.yarnBerryConfigHook
    yarn-berry
    python3
    makeWrapper
  ];

  buildInputs = [
    nodejs
    libusb1
    udev
  ];

  missingHashes = ./missing-hashes.json;

  offlineCache = yarn-berry.fetchYarnBerryDeps {
    inherit src missingHashes;
    hash = "sha256-90nfhX7heHfwgze2Rmbc9YCFcifql6VkaLbToUyxtqY=";
  };

  env = {
    # electron is a devDependency of the satellite workspace; skip its
    # binary download during the offline install (it is never used).
    ELECTRON_SKIP_BINARY_DOWNLOAD = 1;
  };

  # with dontConfigure the yarnBerryConfigHook doesn't retrieve node_modules,
  # so use an empty configurePhase instead (same as bitfocus-companion)
  configurePhase = ''
    runHook preConfigure
    runHook postConfigure
  '';

  buildPhase = ''
    runHook preBuild

    # compile the satellite backend (tsc project references)
    yarn run build:ts

    # build the web UI (served by the built-in REST server on port 9999)
    yarn workspace webui build

    # bundle the surface-thread child-process entrypoint; normally done by
    # tools/build_electron.mts, which we bypass entirely (no electron build)
    printf '%s\n' \
      "import { buildSurfaceThreadEntrypoint } from './build_thread.mts'" \
      "await buildSurfaceThreadEntrypoint()" \
      > tools/nix_build_thread.mts
    yarn tsx tools/nix_build_thread.mts

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    # Runtime layout expected by the "Pi headless" code paths:
    #   <root>/satellite/dist/main.js   - entrypoint
    #   <root>/satellite/dist/surface-entrypoint.mjs
    #   <root>/node_modules             - hoisted deps (patched, see postPatch)
    #   <root>/webui/dist               - static web UI
    #   <root>/assets/nodejs-versions.json
    #   <root>/modules                  - builtin surface plugins
    mkdir -p $out/share/companion-satellite
    cp -r assets node_modules satellite webui $out/share/companion-satellite/

    # dev-only trees, not needed at runtime
    rm -rf \
      $out/share/companion-satellite/webui/node_modules \
      $out/share/companion-satellite/webui/src \
      $out/share/companion-satellite/satellite/src

    mkdir -p $out/share/companion-satellite/modules
    cp -r ${builtinSurfaces}/. $out/share/companion-satellite/modules/

    # udev rules for the supported USB surfaces; these grant access to the
    # 'satellite' group (created by the NixOS module)
    install -Dm644 satellite/assets/linux/50-satellite.rules \
      $out/etc/udev/rules.d/50-satellite.rules

    makeWrapper ${lib.getExe nodejs} $out/bin/companion-satellite \
      --add-flags $out/share/companion-satellite/satellite/dist/main.js \
      --set LD_LIBRARY_PATH "${lib.makeLibraryPath [ libusb1 udev ]}"

    runHook postInstall
  '';

  meta = {
    description = "Satellite Stream Deck (and other surfaces) connector for Bitfocus Companion";
    longDescription = ''
      A small application for connecting Elgato Stream Deck and other supported
      surfaces to Bitfocus Companion over a network. Each surface appears in
      Companion as its own 'satellite' surface. Configuration happens through
      a web UI (default port 9999); the connection to Companion uses TCP 16622.
    '';
    homepage = "https://github.com/bitfocus/companion-satellite";
    license = lib.licenses.mit;
    mainProgram = "companion-satellite";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
