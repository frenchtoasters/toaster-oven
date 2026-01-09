{ pkgs, ... }:
let
  exoBootstrap = pkgs.writeShellApplication {
    name = "exo-bootstrap";
    runtimeInputs = with pkgs; [ bash coreutils curl ];
    text = builtins.readFile ../scripts/exo-bootstrap.sh;
  };
in
{
  environment.systemPackages = [ exoBootstrap ];
}
