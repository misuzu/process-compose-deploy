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
