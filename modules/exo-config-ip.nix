{ pkgs, lib, ... }:
let
  script = pkgs.writeShellScript "exo-config-ip" (builtins.readFile ../scripts/exo-config-ip.sh);
in
{
  launchd.daemons."exo-config-ip" = {
    script = "${script}";
    serviceConfig = {
      RunAtLoad = true;
      StartInterval = 300;
      StandardOutPath = "/var/log/exo-config-ip.out.log";
      StandardErrorPath = "/var/log/exo-config-ip.err.log";
    };
  };
}
