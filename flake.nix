{
  description = "PaddlePaddle nix flake";

  # Nixpkgs / NixOS version to use.
  inputs.nixpkgs.url = "nixpkgs/nixos-22.05";
  inputs.threadPoolSrc.url = "github:progschj/ThreadPool";
  inputs.threadPoolSrc.flake = false;
  inputs.warpctcSrc.url = "github:baidu-research/warp-ctc";
  inputs.warpctcSrc.flake = false;
  inputs.libtorch.url = "github:jinnah-pk/libtorch-nix/main";
  inputs.dlpackSrc.url = "github:dmlc/dlpack";
  inputs.dlpackSrc.flake = false;
  outputs = inputs@{ self, nixpkgs, threadPoolSrc, warpctcSrc, libtorch, dlpackSrc, ... }:
    let

      # to work with older version of flakes
      lastModifiedDate = self.lastModifiedDate or self.lastModified or "19700101";

      # Generate a user-friendly version number.
      version = builtins.substring 0 8 lastModifiedDate;

      # System types to support.
      supportedSystems = [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; overlays = [ self.overlay ]; });

    in

    {

      # A Nixpkgs overlay.
      overlay = final: prev: {

        dlpack = with final; stdenv.mkDerivation {
          name = "dlpack";
          src = dlpackSrc;
          nativeBuildInputs = [ cmake git ];
        };
        warpctc = with final; stdenv.mkDerivation rec {
          pname = "warp-ctc";
          version = "1.0";
          src = warpctcSrc.outPath;
          nativeBuildInputs = [ cmake ninja luajit ];
          buildInputs = [];
          patches = [ ./nix/warp-ctc.patch ];
        };
        threadPool  = with final; stdenv.mkDerivation rec {
          pname = "thread-pool";
          version = "1.0";
          src = threadPoolSrc.outPath;
          nativeBuildInputs = [ gcc ];
          installPhase = ''
            mkdir -p $out/include
            cp -r $src/ $out/include
          '';
        };
        paddleEnv = final.python3.withPackages (ps: with ps; [
          wheel pip numpy protobuf pyyaml jinja2 typing-extensions
        ]);
        paddle = with final; stdenv.mkDerivation rec {
          pname = "PaddlePaddle";
          inherit version;
          src = ./.;
          nativeBuildInputs = [ cmake ninja paddleEnv ];
          buildInputs = [ git cacert paddleEnv protobuf gflags eigen threadPool warpctc dlpack ];
        };

      };

      # Provide some binary packages for selected system types.
      packages = forAllSystems (system:
        {
          inherit (nixpkgsFor.${system}) paddle;
        });

      # The default package for 'nix build'. This makes sense if the
      # flake provides only one package or there is a clear "main"
      # package.
      defaultPackage = forAllSystems (system: self.packages.${system}.paddle);

      # A NixOS module, if applicable (e.g. if the package provides a system service).
      nixosModules.paddle =
        { pkgs, ... }:
        {
          nixpkgs.overlays = [ self.overlay ];

          environment.systemPackages = [ pkgs.paddle ];

          #systemd.services = { ... };
        };

      # Tests run by 'nix flake check' and by Hydra.
      checks = forAllSystems
        (system:
          with nixpkgsFor.${system};

          {
            inherit (self.packages.${system}) paddle;

            # Additional tests, if applicable.
            test = stdenv.mkDerivation {
              pname = "paddle-test";
              inherit version;

              buildInputs = [ paddle ];

              dontUnpack = true;

              buildPhase = ''
                echo 'running some integration tests'
                [[ $(paddle) = 'Paddle Nixers!' ]]
              '';

              installPhase = "mkdir -p $out";
            };
          }

          // lib.optionalAttrs stdenv.isLinux {
            # A VM test of the NixOS module.
            vmTest =
              with import (nixpkgs + "/nixos/lib/testing-python.nix") {
                inherit system;
              };

              makeTest {
                nodes = {
                  client = { ... }: {
                    imports = [ self.nixosModules.paddle ];
                  };
                };

                testScript =
                  ''
                    start_all()
                    client.wait_for_unit("multi-user.target")
                    client.succeed("paddle")
                  '';
              };
          }
        );

    };
}
