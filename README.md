# companion-satellite flake

Builds [Bitfocus Companion Satellite](https://github.com/bitfocus/companion-satellite)
(v3.1.0) from source and provides a NixOS module, modeled on the existing
`bitfocus-companion` package (same yarn-berry offline-cache approach, same
class of patches: no runtime node downloads, no surface-module downloads,
nix-provided node for plugin child processes).

Satellite is a yarn 4 workspace (`satellite` backend + `webui`). The headless
build skips electron entirely: `tsc` for the backend, `vite` for the web UI,
plus an esbuild bundle of the surface-thread child-process entrypoint that
upstream normally produces inside its electron packaging script.

## One-time hash bootstrap

Two hashes can't be precomputed here and use placeholders. In order:

1. **missing-hashes.json** — the lockfile has entries without checksums
   (platform-conditional packages: `@esbuild/*`, rollup binaries, napi
   prebuilds). Generate it the same way as for your companion package:

   ```sh
   curl -LO https://raw.githubusercontent.com/bitfocus/companion-satellite/v3.1.0/yarn.lock
   nix run "nixpkgs#yarn-berry_4.yarn-berry-fetcher" -- missing-hashes yarn.lock \
     > pkgs/companion-satellite/missing-hashes.json
   ```

2. **offlineCache hash** — `package.nix` has `hash = lib.fakeHash` in
   `fetchYarnBerryDeps`. Run `nix build .#companion-satellite`, and copy the
   correct hash from the mismatch error into `package.nix`.

The `src` hash was computed from the v3.1.0 tree and should be correct; if it
ever mismatches, take the value nix prints. The builtin surface-module hashes
are copied verbatim from upstream's `assets/builtin-surface-modules.json`.

## Usage

In your system flake:

```nix
{
  inputs.companion-satellite = {
    url = "github:mrobbetts/companion-satellite-flake"; # or a local path
    inputs.nixpkgs.follows = "nixpkgs";                 # recommended
  };

  # in your nixosConfigurations.<host> modules list:
  #   inputs.companion-satellite.nixosModules.default
}
```

Then in `configuration.nix`:

```nix
services.companion-satellite = {
  enable = true;
  openFirewall = true; # web UI on :9999 + mDNS discovery
};
```

The service runs with `DynamicUser` and `StateDirectory=companion-satellite`,
so its config lives at `/var/lib/companion-satellite/config.json`. Point it at
your Companion instance via the web UI at `http://<host>:9999` (or edit the
JSON and restart). Companion ≥ 3.4 will also discover it via mDNS and offer to
configure it.

## USB surface access

The package ships upstream's `50-satellite.rules` udev rules, which the module
installs via `services.udev.packages`. The rules grant hidraw devices to a
`satellite` group; the module creates that group and runs the service with
`SupplementaryGroups = [ "satellite" "input" ]`, so Stream Decks and friends
work without running as root. If a surface isn't picked up after plugging in,
check `udevadm info` for its vendor/product ID against the rules file.

## Raspberry Pi 3B notes

The package builds for `aarch64-linux` (make sure the Pi runs a 64-bit
system). The yarn lockfile's `supportedArchitectures` already includes arm64,
so the offline cache covers both platforms with the same hash. A 1 GB Pi 3B
will struggle to build the web UI, so build on your x86 machine either via
`boot.binfmt.emulatedSystems = [ "aarch64-linux" ]` plus
`nix build .#packages.aarch64-linux.companion-satellite`, or by using the Pi
as a `nix.distributedBuilds` target in reverse (x86 host builds, Pi pulls),
e.g. `nixos-rebuild --target-host pi --build-host localhost`.

## Updating

Bump `version` and the `src` hash (there's a `nix-update-script` passthru),
regenerate `missing-hashes.json` and the `offlineCache` hash, and re-sync the
`builtinSurfaceModules` list against `assets/builtin-surface-modules.json` in
the new tag.

## What is patched and why

- `package.json` postinstall: runs husky (needs `.git`) and a prepare script
  that downloads node runtimes and surface modules → replaced with a no-op.
- `satellite/src/node-path.ts` (`getNodeJsPath`): surface plugins run as child
  processes under a node binary normally shipped in `node-runtimes/` →
  patched to always use the nix node.
- `satellite/src/node-path.ts` (`getChildNodePath`): the headless layout
  expects `node_modules` inside `satellite/`, but a source build hoists it to
  the workspace root → path adjusted one level up.
- Builtin surface modules (Stream Deck, Loupedeck, X-keys, …) are fetched as
  fixed-output derivations and installed to `<root>/modules`, which the plugin
  loader scans first.
