{
  description = "EXO mac fleet via nix-darwin (+ Home Manager)";

  inputs = {
    nixpkgs.url      = "github:NixOS/nixpkgs/nixpkgs-unstable";
    darwin.url       = "github:LnL7/nix-darwin";
    home-manager.url = "github:nix-community/home-manager";
  };

  outputs = { self, nixpkgs, darwin, home-manager, ... }:
  let
    commonPackages = pkgs: with pkgs; [
      git jq tmux htop coreutils
    ];

    exoProcess = pkgs: pkgs.writeShellApplication {
      name = "exo-process";
      runtimeInputs = with pkgs; [ bash coreutils ];
      text = builtins.readFile ./scripts/exo_process.sh;
    };

    mkHost = {
      hostName,
      userName,
      userEmail ? "toast@frenchtoastman.com",
      system ? "aarch64-darwin",
      authorizedPubKeys ? [],
      extraAuthorizedKeys ? {}
    }:
      darwin.lib.darwinSystem {
        inherit system;
        modules = [
          home-manager.darwinModules.home-manager

          ({ pkgs, lib, ... }: {
            system.stateVersion = 5;
            system.primaryUser  = userName;
            networking.hostName = hostName;

            # Determinate Nix is installed -> nix-darwin should not manage Nix itself.
            nix.enable = false;

            programs.zsh.enable = true;

            environment.systemPackages =
              (commonPackages pkgs) ++ [
                (exoProcess pkgs)
              ];

            # Homebrew is used for exo-from-source prerequisites (uv/macmon/node/git)
            # Note: nix-darwin manages packages but does not install Homebrew itself.
            homebrew = {
              enable = true;
              onActivation = {
                autoUpdate = true;
                upgrade = false;
                cleanup = "zap";
              };
              brews = [ "uv" "macmon" "node" "git" ];
            };

            users.users.${userName} = {
              home = "/Users/${userName}";
              isHidden = false;
              shell = pkgs.zsh;
            };

            # SSH (password login allowed)
            services.openssh = {
              enable = true;
              extraConfig = ''
                PermitRootLogin no
                PasswordAuthentication yes
                KbdInteractiveAuthentication yes
                UsePAM yes
                MaxAuthTries 3
                LoginGraceTime 30s
                MaxStartups 10:30:60
                PermitEmptyPasswords no
                AuthorizedKeysFile .ssh/authorized_keys .ssh/authorized_keys2 /etc/ssh/authorized_keys/%u
              '';
            };

            # /etc entries (+ extra per-user authorized_keys)
            environment.etc = lib.mkMerge [
              {
                "ssh/authorized_keys/${userName}".text = lib.concatStringsSep "\n" authorizedPubKeys + "\n";
                "sudoers.d/10-admin-nopasswd".text = ''
                  %admin ALL=(ALL) NOPASSWD: ALL
                '';
              }
              (lib.listToAttrs (
                lib.mapAttrsToList
                  (uname: keys: {
                    name  = "ssh/authorized_keys/${uname}";
                    value = { text = lib.concatStringsSep "\n" keys + "\n"; };
                  })
                  extraAuthorizedKeys
              ))
            ];

            # Migrate existing /etc/ssh authorized_keys files once (if not symlinked)
            system.activationScripts.migrateEtcAuthorizedKeys.text =
              (let users = [ userName ] ++ (builtins.attrNames extraAuthorizedKeys);
               in ''
                 /bin/mkdir -p /etc/ssh/authorized_keys
                 for u in ${lib.concatStringsSep " " users}; do
                   f="/etc/ssh/authorized_keys/$u"
                   if [ -e "$f" ] && [ ! -L "$f" ]; then
                     /bin/mv "$f" "$f.before-nix-darwin" || true
                   fi
                 done
               '');

            services.tailscale.enable = true;

            # Stay awake
            system.activationScripts.power.text = ''
              /usr/bin/pmset -a sleep 0 displaysleep 0 disksleep 0 >/dev/null 2>&1 || true
            '';

            # macOS defaults
            system.defaults = {
              NSGlobalDomain = {
                AppleShowAllExtensions = true;
                InitialKeyRepeat = 15;
                KeyRepeat = 2;
                NSAutomaticSpellingCorrectionEnabled = false;
              };
              dock = {
                autohide = true;
                show-recents = false;
              };
              finder = {
                AppleShowAllFiles = true;
                FXPreferredViewStyle = "clmv";
                ShowPathbar = true;
                ShowStatusBar = true;
              };
            };

            home-manager.useGlobalPkgs   = true;
            home-manager.useUserPackages = true;
            home-manager.backupFileExtension = "pre-hm";

            home-manager.users.${userName} = { pkgs, ... }: {
              home.stateVersion = "24.05";

              programs.git = {
                enable = true;
                settings = {
                  user = { name = userName; email = userEmail; };
                  pull.rebase = true;
                  credential.helper = "osxkeychain";
                };
              };

              programs.direnv = {
                enable = true;
                nix-direnv.enable = true;
              };

              programs.zsh = {
                enable = true;
                shellAliases = {
                  ll = "ls -lah";
                };
                oh-my-zsh.enable = true;
              };
            };
          })

          # ---- EXO modules (mac fleet) ----
          (import ./modules/exo-bootstrap.nix)
          (import ./modules/exo-repo-sync.nix)
          (import ./modules/exo-gpu-wired-mem.nix)

          # Optional: keep this module if it exists in your repo
          ({ lib, ... }: {
            imports = lib.optional (builtins.pathExists ./modules/exo-config-ip.nix) ./modules/exo-config-ip.nix;
          })

          # ---- Per-host overrides go last ----
          ({ lib, ... }: {
            # Put per-host EnvironmentVariables overrides here if needed.
            # Example: change default branch or GPU memory limits.

            launchd.daemons."exo-gpu-wired-mem".serviceConfig.EnvironmentVariables = {
              WIRED_LIMIT_PERCENT = "90";
              WIRED_LWM_PERCENT   = "80";
            };

            launchd.daemons."exo-repo-sync".serviceConfig.EnvironmentVariables = {
              EXO_REPO_BRANCH = "main";
            };
          })
        ];
      };
  in
  {
    darwinConfigurations."toast" = mkHost {
      hostName = "jeeves-studio-1";
      userName = "toast";
      userEmail = "toast@frenchtoastman.com";
      authorizedPubKeys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDDkE4dX1Zjtn6qnfsjh+5PoR3aJ/85RTeucPsBnBR7XdC85li1/lrxvrmSS73BCeay2TDV6BeBAfFvg9yFWsz8gDllKmA2yqiZzlSMSzzItoDCuErqrfca+z5Fiww85iL8q81CALeqb6F5kRRBCVqwreIioJMByHjzVNEjUH5iCOILNJD/rbVL/DkPO0uWxzoAdmlZCAyz8dCu667SwMtfnXXUjxLH714AyLwQw7lDrUCYT34iilBEN3GMpzw7ZaTob2MKxq9ww3zpDr5FuI7wHS6D8dsGQtovx+YwDbApUxe5bqaFOLrdIqv0nt5WHpOqTG68rzK5yiXJh3+QW+uyI7AwavvVoT86INCm23a6DjeLjXvm7nSCFJEAbdN3+a5GXufqFMuB74zt6blDrew1DxkUnkJSTsi/CBjZmBCJdINm+IU1qhwsH0gFgXqrPIpT0Kei8Ul3XvEXGVljd2yrmbuZ0jg3NeGhSMnJf24iSxWwIflK8NUrDvzTmmxcftU="
      ];
    };

    darwinConfigurations."toast2" = mkHost {
      hostName = "jeeves-studio-2";
      userName = "toast";
      userEmail = "toast@frenchtoastman.com";
      authorizedPubKeys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDDkE4dX1Zjtn6qnfsjh+5PoR3aJ/85RTeucPsBnBR7XdC85li1/lrxvrmSS73BCeay2TDV6BeBAfFvg9yFWsz8gDllKmA2yqiZzlSMSzzItoDCuErqrfca+z5Fiww85iL8q81CALeqb6F5kRRBCVqwreIioJMByHjzVNEjUH5iCOILNJD/rbVL/DkPO0uWxzoAdmlZCAyz8dCu667SwMtfnXXUjxLH714AyLwQw7lDrUCYT34iilBEN3GMpzw7ZaTob2MKxq9ww3zpDr5FuI7wHS6D8dsGQtovx+YwDbApUxe5bqaFOLrdIqv0nt5WHpOqTG68rzK5yiXJh3+QW+uyI7AwavvVoT86INCm23a6DjeLjXvm7nSCFJEAbdN3+a5GXufqFMuB74zt6blDrew1DxkUnkJSTsi/CBjZmBCJdINm+IU1qhwsH0gFgXqrPIpT0Kei8Ul3XvEXGVljd2yrmbuZ0jg3NeGhSMnJf24iSxWwIflK8NUrDvzTmmxcftU="
      ];
    };
  };
}
