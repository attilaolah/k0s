# Nix flake to build `k0s`

This repo contains a Nix flake for building `k0s`, the "zero friction Kubernetes".

The main goal is to leverage the NixOS build toolchains, which allows for easy cross-compiling for architectures like
`i686`, which is not supported by the upstream build toolchain.
