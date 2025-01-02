# https://github.com/Platonic-Systems/process-compose-flake/blob/main/example/flake.nix
{
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  inputs.process-compose-flake.url = "github:Platonic-Systems/process-compose-flake";

  inputs.chinookDb.url = "github:lerocha/chinook-database";
  inputs.chinookDb.flake = false;

  outputs =
    inputs:
    let
      supportedSystems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-darwin"
        "x86_64-linux"
      ];
      forAllSystems = inputs.nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = inputs.nixpkgs.legacyPackages.${system};
          inherit (pkgs) lib;
        in
        {
          # nix run .#default up to start the process
          default = (import inputs.process-compose-flake.lib { inherit pkgs; }).makeProcessCompose {
            modules = [
              {
                settings =
                  let
                    port = 8213;
                    dataFile = "data.sqlite";
                  in
                  {
                    processes = {
                      # Create .sqlite database from chinook database.
                      sqlite-init.command = ''
                        echo "$(date): Importing Chinook database (${dataFile}) ..."
                        ${lib.getExe pkgs.sqlite} "${dataFile}" < ${inputs.chinookDb}/ChinookDatabase/DataSources/Chinook_Sqlite.sql
                        echo "$(date): Done."
                      '';

                      # Run sqlite-web on the local chinook database.
                      sqlite-web = {
                        command = ''
                          ${pkgs.sqlite-web}/bin/sqlite_web \
                            --host 0.0.0.0 \
                            --port ${builtins.toString port} "${dataFile}"
                        '';
                        # The 'depends_on' will have this process wait until the above one is completed.
                        depends_on."sqlite-init".condition = "process_completed_successfully";
                        readiness_probe.http_get = {
                          host = "localhost";
                          inherit port;
                        };
                      };
                    };
                  };
              }
            ];
          };
        }
      );
    };
}