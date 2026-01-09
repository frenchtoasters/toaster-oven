{ pkgs, ... }:
let
  exoGpuWiredMem = pkgs.writeShellApplication {
    name = "exo-gpu-wired-mem";
    runtimeInputs = with pkgs; [ bash coreutils ];
    text = builtins.readFile ../scripts/exo-gpu-wired-mem.sh;
  };
in
{
  environment.systemPackages = [ exoGpuWiredMem ];

  launchd.daemons."exo-gpu-wired-mem" = {
    script = "${exoGpuWiredMem}/bin/exo-gpu-wired-mem";
    serviceConfig = {
      RunAtLoad = true;
      StandardOutPath  = "/var/log/exo-gpu-wired-mem.log";
      StandardErrorPath = "/var/log/exo-gpu-wired-mem.err";
      EnvironmentVariables = {
        WIRED_LIMIT_PERCENT = "90";
        WIRED_LWM_PERCENT   = "80";
      };
    };
  };
}
