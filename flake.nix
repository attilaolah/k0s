{
  description = "K0s build flake";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = inputs @ {
    self,
    flake-parts,
    ...
  }:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "i686-linux"];
      perSystem = {pkgs, ...}: let
        inherit (builtins) elemAt;
        renovate = ["k0sproject/k0s" "1.33.4+k0s.0"]; # github-releases
        ownerAndRepo = pkgs.lib.strings.splitString "/" (elemAt renovate 0);
        owner = elemAt ownerAndRepo 0;
        repo = elemAt ownerAndRepo 1;
        version = elemAt renovate 1;

        pname = repo;
        description = "The Zero Friction Kubernetes";
        homepage = "https://${owner}.io";
        license = pkgs.lib.licenses.asl20;
      in {
        packages.default = with pkgs; let
          module = buildGoModule rec {
            inherit pname version;

            src = fetchFromGitHub {
              inherit owner repo;
              rev = "v${version}";
              hash = "sha256-VMIQbDVyzPg/a8v8jOz8FT8VWaWuZgfnHDvknIzTxzc=";
            };

            vendorHash = "sha256-oe6BisSnlyO/N1DV6W9qHiOW2wWUK1Wf+xyhfxiuso8=";

            GOFLAGS = [
              "-tags=osusergo,noembedbins"
              "-buildvcs=false"
              "-o=${pname}"
            ];

            installPhase = ''
              runHook preInstall

              find .
              install -Dm755 "${pname}" "$out/bin/${pname}"

              runHook postInstall
            '';

            buildInputs = [musl];
            ldflags = let
              inherit (builtins) elemAt split;
              k8sVer = elemAt (split "\\+" version) 0;
              k8sMajor = elemAt (split "\\." k8sVer) 0;
              k8sMinor = elemAt (split "\\." k8sVer) 2;
            in
              ["-s" "-w" "-extldflags=-static"]
              ++ (lib.mapAttrsToList (k: v: "-X ${k}=${v}") {
                "github.com/k0sproject/k0s/pkg/build.Version" = "v${version}";
                "k8s.io/component-base/version.buildDate" = "1970-01-01T00:00:00Z";
                "k8s.io/component-base/version.gitMajor" = k8sMajor;
                "k8s.io/component-base/version.gitMinor" = k8sMinor;
                "k8s.io/component-base/version.gitVersion" = "v${k8sVer}";
              });

            meta = {
              inherit license description homepage;
              mainProgram = pname;
              maintainers = with lib.maintainers; [attila];
              platforms = with lib.platforms; linux ++ darwin;
            };
          };
        in
          module.overrideAttrs (old: {
            buildPhase =
              lib.replaceStrings [
                "getGoDirs() {"
                "buildGoDir install"
              ] [
                # Replace getGoDirs() with a simpler one.
                # We don't want to recursively build all directories.
                "getGoDirs() { echo .; }; __unused() {"
                # Don't install binaries, just build them.
                # The upstream package really isn't structured very well.
                "buildGoDir build"
              ]
              old.buildPhase;
          });

        apps = let
          # Signing stuff:
          email = "attila@dorn.haus";
          signingKey = "${email}-67093be0.rsa";

          # Follow the versioning used by k3s.
          # Alpine won't accept the versions used by upstream.
          apkVersion = builtins.replaceStrings ["+${pname}."] ["."] version;

          apkbuildIn = pkgs.writeText "apkbuild.in" ''
            # Maintainer: Attila Oláh <${email}>
            pkgname=${pname}
            pkgver=${apkVersion}
            pkgrel=0
            pkgdesc="${description}"
            url="${homepage}"
            arch="x86_64 x86"
            license="${license.spdxId}"
            depends="openrc kubelet containerd runc"
            makedepends=""
            install=""
            source="${pname}"

            # Package is already tested in the flake build.
            # Here we only have a binary and no way to run tests.
            options="!build !strip !check"

            package() {
                install -Dm755 "$srcdir/$pkgname" "$pkgdir/usr/bin/$pkgname"
            }
          '';

          entrypointSh = pkgs.writeShellScriptBin "entrypoint.sh" ''
            set -euxo pipefail

            export BOOTSTRAP=nobase
            export CBUILDROOT=$PWD/cbuild

            apk update
            apk add abuild

            mkdir -p "$CBUILDROOT/etc/apk/keys"
            cp -a /etc/apk/keys/*.pub "$CBUILDROOT/etc/apk/keys"
            abuild-apk add --quiet --initdb --arch $CHOST --root "$CBUILDROOT"

            cp "${apkbuildIn}" APKBUILD
            chown packager:abuild APKBUILD .
            chmod u+w APKBUILD

            su packager -c "abuild checksum"
            su packager -c "abuild -r"

            cp -rv /home/packager/packages/* dist
            chown -R $UID:$GID dist
          '';

          apkBuildImageName = "${pname}-apk-build";
          apkBuildImage = pkgs.dockerTools.buildImage {
            name = apkBuildImageName;
            tag = "latest";
            fromImage = pkgs.dockerTools.pullImage (let
              renovate = ["alpine" "3.22.1" "sha256:4bcff63911fcb4448bd4fdacec207030997caf25e9bea4045fa6c8c44de311d1"]; # docker
              name = elemAt renovate 0;
              version = elemAt renovate 1;
              digest = elemAt renovate 2;
            in {
              imageName = name;
              imageDigest = digest;
              sha256 = "sha256-oBoU1GqTLZGH8N3TJKoQCjmpkefCzhHFU3DU5etu7zc=";
              finalImageName = name;
              finalImageTag = version;
              os = "linux";
              arch = "amd64";
            });

            runAsRoot = ''
              /bin/echo "PACKAGER_PRIVKEY=/etc/apk/keys/${signingKey}" > /etc/abuild.conf
              /usr/sbin/adduser -D -G abuild packager
            '';

            copyToRoot = pkgs.buildEnv {
              name = "image-root";
              paths = [entrypointSh];
            };

            config = {
              WorkingDir = "/build";
              Volumes = {"/build" = {};};
              EntryPoint = ["${pkgs.lib.getExe entrypointSh}"];
            };
          };

          app = system: let
            binary = pkgs.lib.getExe self.packages."${system}-linux".default;
            # Convert between Nix & Alpine architectures.
            nix2apk = {
              x86_64 = "x86_64";
              i686 = "x86";
            };
          in {
            type = "app";
            program = pkgs.writeShellApplication {
              name = "build-apk";
              runtimeInputs = with pkgs; [docker];
              text = ''
                host_key="$PWD/keys/${signingKey}"
                guest_key="/etc/apk/keys/${signingKey}"

                docker load < "${apkBuildImage}"
                docker run --rm \
                  --env="UID=$(id -u)" \
                  --env="GID=$(id -g)" \
                  --env="CHOST=${nix2apk.${system}}" \
                  --volume="$host_key:$guest_key" \
                  --volume="$host_key.pub:$guest_key.pub" \
                  --volume="${apkbuildIn}:${apkbuildIn}" \
                  --volume="${binary}:/build/${pname}" \
                  --volume="$PWD/dist:/build/dist" \
                  "${apkBuildImageName}"
              '';
            };
          };
        in {
          i686 = app "i686";
          x86_64 = app "x86_64";
          publish = {
            type = "app";
            program = let
              inherit (pkgs.lib) strings;
              dockerImage = "attilaolah/k0s";
              dockerVersion = strings.concatStrings (strings.splitString "+k0s" version);
              dockerTag = "${dockerImage}:${dockerVersion}";
            in
              pkgs.writeShellApplication {
                name = "apk-repo-build";
                runtimeInputs = with pkgs; [docker nix];
                text = ''
                  rm -rf dist
                  nix run .#i686
                  nix run .#x86_64
                  docker build -t "${dockerTag}" .
                  docker push "${dockerTag}"
                '';
              };
          };
        };
      };
    };
}
