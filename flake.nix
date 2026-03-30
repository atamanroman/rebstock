{
  description = "Rebstock - self-hosted wine inventory manager";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      # NixOS module available for all systems
      nixosModule = { config, lib, pkgs, ... }:
        let
          cfg = config.services.rebstock;
        in
        {
          options.services.rebstock = {
            enable = lib.mkEnableOption "Rebstock wine inventory manager";

            package = lib.mkPackageOption pkgs "rebstock" {
              default = self.packages.${pkgs.system}.default;
            };

            port = lib.mkOption {
              type = lib.types.port;
              default = 3000;
              description = "Port to listen on.";
            };

            dataDir = lib.mkOption {
              type = lib.types.path;
              default = "/var/lib/rebstock";
              description = "Directory for the SQLite database and runtime data.";
            };

            configFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              description = "Path to config.json. If null, a default config is generated.";
            };

            auth = lib.mkOption {
              type = lib.types.submodule {
                options = {
                  mode = lib.mkOption {
                    type = lib.types.enum [ "single" "forward" ];
                    default = "single";
                    description = "Authentication mode.";
                  };
                  user = lib.mkOption {
                    type = lib.types.str;
                    default = "admin";
                    description = "Username for single-user auth mode.";
                  };
                  headerUser = lib.mkOption {
                    type = lib.types.str;
                    default = "x-webauth-user";
                    description = "Header for forward auth user.";
                  };
                  headerName = lib.mkOption {
                    type = lib.types.str;
                    default = "x-webauth-name";
                    description = "Header for forward auth display name.";
                  };
                  headerEmail = lib.mkOption {
                    type = lib.types.str;
                    default = "x-webauth-email";
                    description = "Header for forward auth email.";
                  };
                  headerGroups = lib.mkOption {
                    type = lib.types.str;
                    default = "x-webauth-groups";
                    description = "Header for forward auth groups.";
                  };
                };
              };
              default = { };
              description = "Authentication configuration.";
            };
          };

          config = lib.mkIf cfg.enable {
            systemd.services.rebstock = {
              description = "Rebstock wine inventory manager";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];

              serviceConfig = {
                Type = "exec";
                DynamicUser = true;
                StateDirectory = "rebstock";
                WorkingDirectory = cfg.dataDir;
                ExecStart =
                  let
                    configJson =
                      if cfg.configFile != null then cfg.configFile
                      else pkgs.writeText "rebstock-config.json" (builtins.toJSON ({
                        port = cfg.port;
                        database_uri = "file:${cfg.dataDir}/rebstock.db";
                        auth =
                          if cfg.auth.mode == "single" then {
                            single = { user = cfg.auth.user; };
                          } else {
                            forward = {
                              header_user = cfg.auth.headerUser;
                              header_name = cfg.auth.headerName;
                              header_email = cfg.auth.headerEmail;
                              header_groups = cfg.auth.headerGroups;
                            };
                          };
                      }));
                  in
                  "${cfg.package}/bin/rebstock --config ${configJson}";
                Restart = "on-failure";
                RestartSec = 5;

                # Hardening
                NoNewPrivileges = true;
                ProtectSystem = "strict";
                ProtectHome = true;
                ReadWritePaths = [ cfg.dataDir ];
                PrivateTmp = true;
                PrivateDevices = true;
                ProtectKernelTunables = true;
                ProtectControlGroups = true;
                RestrictSUIDSGID = true;
              };
            };
          };
        };
    in
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          config.allowUnfreePredicate = pkg:
            builtins.elem (nixpkgs.lib.getName pkg) [ "rebstock" "rebstock-deps" ];
        };

        version =
          let
            env = builtins.getEnv "REBSTOCK_VERSION";
            d = self.lastModifiedDate or "19700101000000";
            date = "${builtins.substring 0 4 d}-${builtins.substring 4 2 d}-${builtins.substring 6 2 d}";
            shortRev = self.shortRev or "dirty";
          in
          if env != "" then env else "${date}-dev-${shortRev}";

        # Fixed-output derivation to fetch hex dependencies
        deps = pkgs.stdenv.mkDerivation {
          pname = "rebstock-deps";
          inherit version;
          src = pkgs.lib.cleanSourceWith {
            src = ./.;
            filter = path: type:
              let name = builtins.baseNameOf path; in
              name == "gleam.toml" || name == "manifest.toml";
          };

          nativeBuildInputs = [ pkgs.gleam pkgs.erlang ];

          outputHashAlgo = "sha256";
          outputHashMode = "recursive";
          outputHash = pkgs.lib.fakeHash;

          buildPhase = ''
            export HOME=$TMPDIR
            gleam deps download
          '';

          installPhase = ''
            mkdir -p $out
            cp -r build/packages/* $out/
          '';
        };

        rebstock = pkgs.stdenv.mkDerivation {
          pname = "rebstock";
          inherit version;

          src = pkgs.lib.cleanSourceWith {
            src = ./.;
            filter = path: type:
              let
                name = builtins.baseNameOf path;
                relPath = pkgs.lib.removePrefix (toString ./. + "/") (toString path);
              in
              # Exclude build artifacts, nix files, dev files, database
              name != "build"
              && name != "flake.nix"
              && name != "flake.lock"
              && name != ".git"
              && name != ".claude"
              && name != "tailwindcss"
              && name != "result"
              && !pkgs.lib.hasSuffix ".db" name
              && !pkgs.lib.hasSuffix ".db-shm" name
              && !pkgs.lib.hasSuffix ".db-wal" name;
          };

          nativeBuildInputs = [
            pkgs.gleam
            pkgs.erlang
            pkgs.rebar3
            pkgs.tailwindcss
            pkgs.makeWrapper
          ];

          configurePhase = ''
            runHook preConfigure

            # Link pre-fetched dependencies
            mkdir -p build/packages
            cp -r ${deps}/* build/packages/
            chmod -R u+w build/packages

            runHook postConfigure
          '';

          buildPhase = ''
            runHook preBuild

            export HOME=$TMPDIR

            # Build CSS with tailwindcss
            mkdir -p priv/static/css
            tailwindcss \
              -i src/css/app.css \
              -o priv/static/css/app.css \
              --content './src/**/*.gleam,./src/**/*.css' \
              --minify

            # Check for warnings, then build the Erlang shipment
            gleam build --warnings-as-errors
            gleam export erlang-shipment

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall

            mkdir -p $out/lib/rebstock
            cp -r build/erlang-shipment/* $out/lib/rebstock/

            # Copy priv files (migrations, static assets)
            cp -r priv $out/lib/rebstock/rebstock/

            # Create wrapper script
            mkdir -p $out/bin
            makeWrapper ${pkgs.erlang}/bin/erl $out/bin/rebstock \
              --add-flags "-pa $out/lib/rebstock/*/ebin" \
              --add-flags "-eval 'rebstock@@main:run(rebstock)'" \
              --add-flags "-noshell" \
              --add-flags "-extra"

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Self-hosted wine inventory manager";
            license = { spdxId = "PolyForm-Noncommercial-1.0.0"; free = false; };
            platforms = platforms.unix;
            mainProgram = "rebstock";
          };
        };
      in
      {
        packages = {
          default = rebstock;
          rebstock = rebstock;
        };

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.gleam
            pkgs.erlang
            pkgs.rebar3
            pkgs.tailwindcss
            pkgs.watchexec
            pkgs.just
          ];
        };
      }
    )) // {
      nixosModules.default = nixosModule;
      nixosModules.rebstock = nixosModule;
    };
}
