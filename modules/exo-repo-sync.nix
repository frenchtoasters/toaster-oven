{ config, pkgs, lib, ... }:
let
  user = config.system.primaryUser or "toast";

  exoRepoSync = pkgs.writeShellApplication {
    name = "exo-repo-sync";
    runtimeInputs = with pkgs; [ bash coreutils git gnused gawk curl ];
    text = builtins.readFile ../scripts/exo-repo-sync.sh;
  };

  logDir = "/Users/${user}/Library/Logs";
  outLog = "${logDir}/exo-repo-sync.log";
  errLog = "${logDir}/exo-repo-sync.err";
in
{
  environment.systemPackages = [ exoRepoSync ];

  system.activationScripts.exoRepoSyncLogs.text = ''
    mkdir -p ${logDir}
    chown ${user}:staff ${logDir} || true
  '';

  launchd.daemons."exo-repo-sync" = {
    script = "${exoRepoSync}/bin/exo-repo-sync";

    serviceConfig = {
      UserName = user;
      RunAtLoad = true;
      StartInterval = 900;
      StandardOutPath = outLog;
      StandardErrorPath = errLog;

      # Defaults; override per-host in flake.nix if you want.
      EnvironmentVariables = {
        EXO_REPO_URL_HTTPS = "https://github.com/exo-explore/exo.git";
        EXO_REPO_BRANCH    = "main";
        EXO_REPO_DEST      = "/opt/exo";
        EXO_REPO_OWNER     = user;
      };
    };
  };
}
