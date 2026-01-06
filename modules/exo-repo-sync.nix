{ pkgs, lib, ... }:
let
  script = pkgs.writeShellScript "exo-repo-sync" (builtins.readFile ../scripts/exo-repo-sync.sh);
in
{
  launchd.daemons."exo-repo-sync" = {
    script = "${script}";
    serviceConfig = {
      RunAtLoad = true;
      StartInterval = 900;
      StandardOutPath = "/var/log/exo-repo-sync.out.log";
      StandardErrorPath = "/var/log/exo-repo-sync.err.log";
    };
  };
}
