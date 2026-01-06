{ config, lib, pkgs, ... }:
let
  syncImpl = pkgs.writeShellScript "exo-repo-sync-linux-impl" (builtins.readFile ../scripts/exo-repo-sync-linux.sh);
  exoRepoSyncBin = pkgs.writeShellScriptBin "exo-repo-sync" ''
    exec ${syncImpl}
  '';
in
{
  # Ensure user services start/stop on switch
  systemd.user.startServices = "sd-switch";

  home.packages = [
    pkgs.git
    exoRepoSyncBin
  ];

  systemd.user.services."org.nixos.exo-repo-sync" = {
    Unit = {
      Description = "EXO repo sync (Linux)";
      After = [ "network-online.target" ];
      Wants = [ "network-online.target" ];
    };
    Service = {
      Type = "oneshot";
      Environment = [
        "EXO_REPO_URL_HTTPS=https://github.com/exo-explore/exo-v2.git"
        "EXO_REPO_BRANCH=big-refactor"
        "EXO_REPO_DEST=/opt/exo"
      ];
      ExecStart = "${syncImpl}";
    };
  };

  systemd.user.timers."org.nixos.exo-repo-sync" = {
    Unit = {
      Description = "EXO repo sync timer (Linux)";
    };
    Timer = {
      OnBootSec = "1m";
      OnUnitActiveSec = "900s";
      Persistent = true;
    };
    Install = {
      WantedBy = [ "timers.target" ];
    };
  };
}
