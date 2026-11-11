{
  description = "Rebstock - self-hosted wine inventory manager";

  inputs = {
    self.submodules = true;
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

            host = lib.mkOption {
              type = lib.types.str;
              default = "127.0.0.1";
              description = "IP to bind to (0.0.0.0 for all interfaces).";
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

            mcp = lib.mkOption {
              type = lib.types.nullOr (lib.types.submodule {
                options = {
                  resource = lib.mkOption {
                    type = lib.types.str;
                    description = "Public MCP resource URL and access-token audience.";
                  };
                  issuer = lib.mkOption {
                    type = lib.types.str;
                    description = "Exact OAuth access-token issuer.";
                  };
                  jwksUri = lib.mkOption {
                    type = lib.types.str;
                    description = "Fixed HTTPS issuer signing-key endpoint.";
                  };
                  clientId = lib.mkOption {
                    type = lib.types.str;
                    description = "Allowed public OAuth client identifier.";
                  };
                  scope = lib.mkOption {
                    type = lib.types.str;
                    description = "Required application-specific OAuth scope.";
                  };
                  usernameClaim = lib.mkOption {
                    type = lib.types.str;
                    description = "Verified access-token claim identifying the Rebstock user.";
                  };
                };
              });
              default = null;
              description = "MCP OAuth configuration; null disables MCP independently of web authentication.";
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
                        host = cfg.host;
                        port = cfg.port;
                        database_uri = "file:${cfg.dataDir}/rebstock.db";
                        image_dir = "${cfg.dataDir}/images";
                        mcp = if cfg.mcp == null then null else {
                          resource = cfg.mcp.resource;
                          issuer = cfg.mcp.issuer;
                          jwks_uri = cfg.mcp.jwksUri;
                          client_id = cfg.mcp.clientId;
                          scope = cfg.mcp.scope;
                          username_claim = cfg.mcp.usernameClaim;
                        };
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
          config.allowUnfree = true;
        };

        inherit (pkgs) lib;

        zolaSrc = pkgs.fetchFromGitHub {
          owner = "getzola";
          repo = "zola";
          rev = "v0.23.2";
          hash = "sha256-pdePZ8w+cUXA62wkCqtSBwtHNCBSmJQ0kqyOq+0k06o=";
        };

        zola = pkgs.zola.overrideAttrs {
          version = "0.23.2";
          src = zolaSrc;
          doCheck = false;
          cargoDeps = pkgs.rustPlatform.fetchCargoVendor {
            src = zolaSrc;
            hash = "sha256-KTDsj6mOh8x4JtUL52lLARszmvMyvC49+MlnwHYaSq4=";
          };
        };

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
              let
                name = builtins.baseNameOf path;
                relative = lib.removePrefix (toString ./. + "/") (toString path);
                siteOnly = relative == ".gitmodules"
                  || relative == "site"
                  || lib.hasPrefix "site/" relative;
              in
              !siteOnly
              && name != "build"
              && name != "flake.nix"
              && name != "flake.lock"
              && name != ".git"
              && name != ".claude"
              && name != "result"
              && !lib.hasSuffix ".db" name
              && !lib.hasSuffix ".db-shm" name
              && !lib.hasSuffix ".db-wal" name;
          };

          nativeBuildInputs = [
            pkgs.gleam
            pkgs.erlang
            (pkgs.rebar3WithPlugins { plugins = [ pkgs.beamPackages.pc ]; })
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
        lint = rebstock.overrideAttrs (old: {
          pname = "rebstock-lint";
          buildPhase = ''
            runHook preBuild

            export HOME=$TMPDIR
            export REBAR_CACHE_DIR="$TMPDIR/.rebar-cache"

            gleam format --check .
            gleam build --warnings-as-errors

            runHook postBuild
          '';
          installPhase = ''
            runHook preInstall
            mkdir -p $out
            touch $out/lint-ok
            runHook postInstall
          '';
        });

        site = pkgs.stdenvNoCC.mkDerivation {
          pname = "rebstock-site";
          version = "0.1.0";
          src = lib.cleanSource ./site;
          nativeBuildInputs = [ zola pkgs.cacert ];

          buildPhase = ''
            runHook preBuild
            zola check --skip-external-links
            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            zola build --output-dir $out
            runHook postInstall
          '';
        };
      in
      {
        packages = {
          default = rebstock;
          inherit rebstock site;
        };

        checks = {
          inherit lint site;
          build = rebstock;
        };

        devShells.default = pkgs.mkShell {
          packages = [
            pkgs.gleam
            pkgs.erlang
            pkgs.rebar3
            pkgs.watchexec
            pkgs.just
            pkgs.lefthook
            pkgs.nodejs
            zola
          ];
        };
      }
    )) // {
      nixosModules.default = nixosModule;
      nixosModules.rebstock = nixosModule;
    } // (let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;

      deploySite = pkgs.stdenvNoCC.mkDerivation {
        name = "deploy-rebstock-site";
        isEffect = true;
        secretsMap = builtins.toJSON {
          cloudflare = "cloudflare";
        };
        nativeBuildInputs = [
          pkgs.cacert
          pkgs.jq
          pkgs.wrangler
        ];
        phases = [
          "initPhase"
          "effectPhase"
        ];

        initPhase = ''
          exec </dev/null
          export HOME=/build/home
          mkdir -p "$HOME"
        '';

        effectPhase = ''
          export CLOUDFLARE_API_TOKEN="$(${pkgs.jq}/bin/jq -er \
            '.cloudflare.data.api_token' "$HERCULES_CI_SECRETS_JSON")"
          export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
          export NODE_EXTRA_CA_CERTS="$SSL_CERT_FILE"

          work=$(mktemp -d)
          mkdir "$work/public"
          cp -R ${self.packages.x86_64-linux.site}/. "$work/public/"
          cp ${./site/wrangler.toml} "$work/wrangler.toml"

          cd "$work"
          ${pkgs.wrangler}/bin/wrangler deploy
        '';
      };
    in
    {
      herculesCI = { primaryRepo, ... }: {
        onPush.default.outputs.effects.deploy =
          if primaryRepo.branch or null == "main" then
            { run = deploySite; }
          else
            {
              dependencies = deploySite.inputDerivation // {
                isEffect = false;
                buildDependenciesOnly = true;
              };
            };
      };
    });
}
