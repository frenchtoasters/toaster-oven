{ pkgs, lib, ... }:
let
  script = pkgs.writeShellScript "exo-gpu-wired-mem" (builtins.readFile ../scripts/exo-gpu-wired-mem.sh);
in
{
  # Run once at boot (and you can add StartInterval if you want periodic re-apply)
  launchd.daemons."exo-gpu-wired-mem" = {
    command = "${pkgs.bash}/bin/bash -lc '${script}'";
    serviceConfig = {
      RunAtLoad = true;

      # optional: re-apply every 15 minutes
      # StartInterval = 900;

      StandardOutPath  = "/var/log/exo-gpu-wired-mem.log";
      StandardErrorPath = "/var/log/exo-gpu-wired-mem.err";
      # You can override these per-host in flake.nix
      EnvironmentVariables = {
        WIRED_LIMIT_PERCENT = "90";
        WIRED_LWM_PERCENT   = "80";
      };
    };
  };
}
