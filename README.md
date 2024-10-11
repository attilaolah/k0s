# Nix flake to build `k0s`

This repo contains a Nix flake for building `k0s`, the "zero friction Kubernetes".

The main goal is to leverage the NixOS build toolchains, which allows for easy cross-compilation for architectures that
are not supported by the upstream project, i.e. `i686`.

## Runtime Dependencies

The binary that is built is the "minimal" version, which does not bundle its dependencies (however, it is still
statically linked). Depending on the usage, different dependencies are required:

- `runc` if using the default low-level runtime
- `containerd` if using the default CRI (not needed if using e.g. Docker or CRI-O)
- `kine` if running a control plane node with the SQLite backend
- `etcd` if running a control plane node with etcd backend
- `konnectivity` if enabled via config

All these binaries can be made available at runtime as needed.

## Alpine Packages

The flake contains "apps" for packaging the binaries as APKs for Alpine. The "keys" directory contains my signing key;
it can be added to `/etc/apk/keys` to verify the signatures.
