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

            package = lib.mkOption {
              type = lib.types.package;
              default = self.packages.${pkgs.stdenv.hostPlatform.system}.default;
              description = "The rebstock package to use.";
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
            builtins.elem (nixpkgs.lib.getName pkg) [ "rebstock" ];
        };

        inherit (pkgs) lib;

        # Parse manifest.toml at eval time to get dependency info
        manifestToml = lib.importTOML ./manifest.toml;
        gleamToml = lib.importTOML ./gleam.toml;

        version = "${gleamToml.version}-${self.shortRev or "dirty"}";

        # Fetch each hex dependency individually using checksums from manifest.toml
        hexPackages = lib.filter (p: p.source == "hex") manifestToml.packages;

        depsDerivs = map (p: {
          name = p.name;
          derivation = pkgs.beamPackages.fetchHex {
            inherit (p) version;
            pkg = p.name;
            sha256 = p.outer_checksum;
          };
        }) hexPackages;

        # Generate packages.toml at eval time from manifest
        packagesTOML = pkgs.writeText "packages.toml" (
          lib.concatStringsSep "\n" (
            [ "[packages]" ]
            ++ (map (p: ''${p.name} = "${p.version}"'') manifestToml.packages)
          )
        );

        rebstock = pkgs.stdenv.mkDerivation {
          pname = "rebstock";
          inherit version;

          src = lib.cleanSourceWith {
            src = ./.;
            filter = path: type:
              let name = builtins.baseNameOf path; in
              name != "build"
              && name != "flake.nix"
              && name != "flake.lock"
              && name != ".git"
              && name != ".claude"
              && name != "tailwindcss"
              && name != "result"
              && !lib.hasSuffix ".db" name
              && !lib.hasSuffix ".db-shm" name
              && !lib.hasSuffix ".db-wal" name;
          };

          nativeBuildInputs = [
            pkgs.gleam
            pkgs.erlang
            (pkgs.rebar3WithPlugins { plugins = [ pkgs.beamPackages.pc ]; })
            pkgs.tailwindcss_4
            pkgs.makeWrapper
            pkgs.rsync
          ];

          configurePhase = ''
            runHook preConfigure

            mkdir -p build/packages
            cp ${packagesTOML} build/packages/packages.toml
            chmod u+w build/packages/packages.toml

            ${lib.concatStringsSep "\n" (map (d: ''
              rsync --chmod=Du=rwx,Dg=rx,Do=rx,Fu=rw,Fg=r,Fo=r -r ${d.derivation}/* build/packages/${d.name}/
            '') depsDerivs)}

            runHook postConfigure
          '';

          buildPhase = ''
            runHook preBuild

            export HOME=$TMPDIR
            export REBAR_CACHE_DIR="$TMPDIR/.rebar-cache"

            # Build CSS with tailwindcss
            mkdir -p priv/static/css
            tailwindcss \
              -i src/css/app.css \
              -o priv/static/css/app.css \
              --content './src/**/*.gleam,./src/**/*.css' \
              --minify

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

          meta = with lib; {
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
            pkgs.lefthook
          ];
        };
      }
    )) // {
      nixosModules.default = nixosModule;
      nixosModules.rebstock = nixosModule;
    };
}
