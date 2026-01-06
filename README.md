# EXO Fleet Bundle (macOS + Linux)

This bundle contains:
- `flake.nix` (patched to import linux repo sync module)
- `modules/`:
  - `exo-config-ip.nix` (launchd daemon wrapper)
  - `exo-repo-sync.nix` (launchd daemon wrapper)
  - `exo-repo-sync-linux.nix` (systemd --user service + timer + exo-repo-sync command)
- `scripts/`:
  - `exo-config-ip.sh` (your original)
  - `exo-repo-sync.sh` (your original)
  - `exo-repo-sync-linux.sh` (linux equivalent)
- `fleet/` orchestrator scripts:
  - `bootstrap.sh`, `update.sh`, `start.sh`, `stop.sh`

Quick start:

```bash
GH_PAT=... ./fleet/bootstrap.sh --hosts ./hosts.txt --pubkey ~/.ssh/id_ed25519.pub --flake-dir .
./fleet/update.sh --hosts ./hosts.txt --branch big-refactor
./fleet/start.sh --hosts ./hosts.txt
```
