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
  imports = [ ./options.nix ];
  config = lib.mkIf (enabledInstances != { }) {
    environment.systemPackages = lib.flatten (
      lib.attrsets.mapAttrsToList (
        name: cfg:
        let
          run-wrapper =
            name: script:
            pkgs.writeShellScriptBin name ''
              set -euo pipefail
              export ${
                lib.concatStringsSep " " (
                  lib.mapAttrsToList (
                    name: value: "${name}=${lib.escapeShellArg (toString value)}"
                  ) cfg.environment
                )
              }
              export PATH=$PATH:${lib.makeBinPath [ pkgs.bash ]}
              cd /var/lib/process-compose/${name}/data
              sudo -E -u daemon ${script} "$@"
            '';
          adminScript = pkgs.writeShellScript "adm-${name}" ''
            set -euo pipefail
            $PC_PROFILE_PATH/bin/* ${lib.optionalString cfg.useUnixSocket "-U"} \
              --log-file "$HOME/client.log" "$@"
          '';
          updateScript = pkgs.writeShellScript "update-${name}" ''
            set -euo pipefail
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
          (run-wrapper "process-compose-adm-${name}" adminScript)
          (run-wrapper "process-compose-deploy-${name}" updateScript)
        ]
      ) enabledInstances
    );

    launchd.daemons = lib.mapAttrs' (
      name: cfg:
      lib.nameValuePair "process-compose-${name}" {
        environment = lib.mapAttrs (_: toString) cfg.environment;
        script = ''
          set -euo pipefail
          export PATH=$PATH:${lib.makeBinPath [ pkgs.bash ]}

          ${lib.optionalString (cfg.environmentFile != null) "source ${cfg.environmentFile}"}

          mkdir -p /var/lib/process-compose/${name}/data
          chown daemon:daemon /var/lib/process-compose/${name} /var/lib/process-compose/${name}/data

          if [ -L "$PC_PROFILE_PATH" ] && [ -e "$PC_PROFILE_PATH" ]; then
            echo "using $(readlink -f "$PC_PROFILE_PATH")"
          else
            rm -f "$PC_PROFILE_PATH"
            ${lib.getExe' config.nix.package "nix-env"} -p "$PC_PROFILE_PATH" --set ${cfg.defaultProfile}
          fi

          cd /var/lib/process-compose/${name}/data

          sudo -E -u daemon $PC_PROFILE_PATH/bin/* ${lib.optionalString cfg.useUnixSocket "-U"} \
            --tui=false \
            --keep-project \
            --ordered-shutdown \
            --disable-dotenv \
            --log-file "$HOME/server.log"
        '';
        serviceConfig = {
          KeepAlive = true;
          RunAtLoad = true;
          StandardOutPath = "/var/log/process-compose-${name}.out.log";
          StandardErrorPath = "/var/log/process-compose-${name}.err.log";
        };
      }
    ) enabledInstances;
  };
}
