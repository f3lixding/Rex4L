# Rex4L

Linux client for the Rex multiplexer, built with Zig and GTK4.

## Development

```sh
nix develop
zig build
zig build run
```

## Nix package

```sh
nix build
nix run
```

`zig2nix` generates the dependency expressions used to populate Zig's cache
before the sandboxed build. Dependency fetching happens in separate fixed-output
Nix derivations; the application build does not need network access.

After changing dependencies in `build.zig.zon`, regenerate both files:

```sh
nix develop -c zig2nix zon2lock build.zig.zon
nix develop -c zig2nix zon2nix build.zig.zon2json-lock
```

Commit `build.zig.zon2json-lock` and `build.zig.zon.nix` alongside the manifest.
