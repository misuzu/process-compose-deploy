{
  config,
  lib,
  pkgs,
  ...
}:
let
  enabledInstances = lib.filterAttrs (name: cfg: cfg.enable) config.services.process-compose-deploy;
in
{
  options.services.process-compose-deploy = lib.mkOption {
    default = { };
    type = lib.types.attrsOf (
      lib.types.submodule (
        { name, ... }:
        {
          options = {
            enable = lib.mkEnableOption "process-compose instance";
            environment = lib.mkOption rec {
              type = lib.types.attrsOf (
                lib.types.oneOf [
                  lib.types.str
                  lib.types.int
                ]
              );
              default = rec {
                HOME = "/var/lib/process-compose/${name}";
                PC_PROFILE_PATH = "${HOME}/profile";
                PC_SOCKET_PATH = "${HOME}/sock";
              };
              example = {
                PC_PORT_NUM = 8080;
              };
              description = ''
                Environment variables for the process-compose.
              '';
              apply = lib.recursiveUpdate default;
            };
            environmentFile = lib.mkOption {
              type = lib.types.nullOr lib.types.path;
              default = null;
              example = "/run/secrets/process-compose.env";
              description = ''
                Environment file to be passed to the systemd service.
                Useful for passing secrets to the service to prevent them from being
                world-readable in the Nix store.
              '';
            };
            useUnixSocket = lib.mkEnableOption "use unix domain sockets instead of tcp" // {
              default = true;
            };
            defaultProfile = lib.mkOption {
              type = lib.types.path;
              default = pkgs.writeShellScriptBin name ''
                export PC_CONFIG_FILES=${
                  builtins.toFile "config.json" (
                    builtins.toJSON {
                      version = "0.5";
                      processes = { };
                    }
                  )
                }
                exec ${lib.getExe pkgs.process-compose} "$@"
              '';
              defaultText = "<process-compose script with empty config>";
              description = ''
                The process-compose-flake instance to start for the first time.
              '';
            };
          };
        }
      )
    );
  };
  config = lib.mkIf (enabledInstances != { }) {
    environment.systemPackages = lib.flatten (
      lib.attrsets.mapAttrsToList (
        name: cfg:
        let
          systemd-run-wrapper =
            name: script:
            pkgs.writeShellScriptBin name ''
              exec systemd-run \
                -u ${name}.service \
                -p Group=process-compose \
                -p User=process-compose \
                ${
                  lib.concatStringsSep " " (
                    lib.mapAttrsToList (
                      name: value: "-E ${name}=${lib.escapeShellArg (toString value)}"
                    ) cfg.environment
                  )
                } -q \
                -t -G --wait --service-type=exec \
                ${script} "$@"
            '';
          adminScript = pkgs.writeShellScript "adm-${name}" ''
            export PATH=$PATH:${lib.makeBinPath [ pkgs.bash ]}
            $PC_PROFILE_PATH/bin/* ${lib.optionalString cfg.useUnixSocket "-U"} \
              --log-file "$HOME/client.log" "$@"
          '';
          updateScript = pkgs.writeShellScript "update-${name}" ''
            if [[ "$1" != /nix/store/* ]]; then
              echo "not a closure: $1"
              exit 1
            fi
            ${lib.getExe' config.nix.package "nix-env"} -p "$PC_PROFILE_PATH" --set "$1"
            ${lib.getExe' config.nix.package "nix-env"} -p "$PC_PROFILE_PATH" --delete-generations +3
            ${adminScript} project update "''${@:1}"
          '';
        in
        [
          (systemd-run-wrapper "process-compose-adm-${name}" adminScript)
          (systemd-run-wrapper "process-compose-deploy-${name}" updateScript)
        ]
      ) enabledInstances
    );

    systemd.services = lib.mapAttrs' (
      name: cfg:
      lib.nameValuePair "process-compose@${name}" {
        description = "process-compose (instance ${name})";
        after = [ "network.target" ];
        wantedBy = [ "multi-user.target" ];
        path = with pkgs; [ bash ];
        environment = lib.mapAttrs (_: toString) cfg.environment;
        preStart = ''
          if [ -L "$PC_PROFILE_PATH" ] && [ -e "$PC_PROFILE_PATH" ]; then
            echo "using $(readlink -f "$PC_PROFILE_PATH")"
          else
            rm -f "$PC_PROFILE_PATH"
            ${lib.getExe' config.nix.package "nix-env"} -p "$PC_PROFILE_PATH" --set ${cfg.defaultProfile}
          fi
        '';
        script = ''
          exec $PC_PROFILE_PATH/bin/* ${lib.optionalString cfg.useUnixSocket "-U"} \
            --tui=false \
            --keep-project \
            --ordered-shutdown \
            --disable-dotenv \
            --log-file "$HOME/server.log"
        '';
        serviceConfig = {
          EnvironmentFile = lib.optional (cfg.environmentFile != null) cfg.environmentFile;
          Type = "exec";
          Restart = "always";
          RestartSec = 1;
          Group = "process-compose";
          User = "process-compose";
          StateDirectory = "process-compose process-compose/${name} process-compose/${name}/data";
          WorkingDirectory = "/var/lib/process-compose/${name}/data";
        };
      }
    ) enabledInstances;

    users.groups.process-compose = { };
    users.users.process-compose = {
      group = "process-compose";
      isSystemUser = true;
    };
  };
}
