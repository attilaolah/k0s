{
  description = "K0s build flake";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = inputs @ {flake-parts, ...}:
    flake-parts.lib.mkFlake {inherit inputs;} {
      systems = ["x86_64-linux" "i686-linux"];
      perSystem = {pkgs, ...}: {
        packages.default = with pkgs; let
          module = buildGoModule rec {
            pname = "k0s";
            version = "1.31.1+k0s.1";

            src = fetchFromGitHub {
              owner = "k0sproject";
              repo = "k0s";
              rev = "v${version}";
              hash = "sha256-QXSvbi11GR0G5aALKz44hoPHDC7TUa05nu2hqUO+jVQ=";
            };

            vendorHash = "sha256-YfVELaOOgGddtGGJIFlYH6Gxcy9eqa+CtZzFXV1YpDo=";

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

            buildInputs = [glibc.static];
            nativeBuildInputs = [musl];
            ldflags = let
              k8sVer = with builtins; elemAt (split "\\+" version) 0;
              k8sMajor = with builtins; elemAt (split "\\." k8sVer) 0;
              k8sMinor = with builtins; elemAt (split "\\." k8sVer) 2;
            in
              ["-s" "-w" "-extldflags=-static"]
              # TODO: -extldflags='-L${musl}/lib'
              ++ (lib.mapAttrsToList (k: v: "-X ${k}=${v}") {
                # TODO: Extract these version tags from the go mod file.
                # Or better yet, patch the mod file to contain our own versions.
                "github.com/containerd/containerd/version.Version" = containerd.version;
                "github.com/k0sproject/k0s/pkg/build.ContainerdVersion" = containerd.version;
                "github.com/k0sproject/k0s/pkg/build.EtcdVersion" = etcd.version;
                "github.com/k0sproject/k0s/pkg/build.EulaNotice" = "";
                "github.com/k0sproject/k0s/pkg/build.KineVersion" = "0.13.2"; # TODO
                "github.com/k0sproject/k0s/pkg/build.KonnectivityVersion" = "0.30.3"; # TODO
                "github.com/k0sproject/k0s/pkg/build.KubernetesVersion" = k8sVer;
                "github.com/k0sproject/k0s/pkg/build.RuncVersion" = runc.version;
                "github.com/k0sproject/k0s/pkg/build.Version" = "v${version}";
                "github.com/k0sproject/k0s/pkg/telemetry.segmentToken" = "";
                "k8s.io/component-base/version.buildDate" = "1970-01-01T00:00:00Z";
                "k8s.io/component-base/version.gitCommit" = "not_available";
                "k8s.io/component-base/version.gitMajor" = k8sMajor;
                "k8s.io/component-base/version.gitMinor" = k8sMinor;
                "k8s.io/component-base/version.gitVersion" = "v${k8sVer}";
              });

            # TODO: Re-enable.
            doCheck = false;

            meta = {
              description = "The Zero Friction Kubernetes";
              homepage = "https://k0sproject.io";
              mainProgram = "k0s";
              license = lib.licenses.asl20;
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
      };
    };
}
