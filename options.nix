{
  lib,
  pkgs,
  ...
}:
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
}
