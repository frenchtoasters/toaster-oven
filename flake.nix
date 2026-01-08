{
  description = "EXO fleet via nix-darwin (+ Home Manager) with IP + repo sync daemons (SSH passwords allowed, multi-pubkey)";

  inputs = {
    nixpkgs.url      = "github:NixOS/nixpkgs/nixpkgs-unstable";
    darwin.url       = "github:LnL7/nix-darwin";
    home-manager.url = "github:nix-community/home-manager";
  };

  outputs = { self, nixpkgs, darwin, home-manager, ... }:
  let
    commonPackages = pkgs: with pkgs; [
      git uv direnv nix-direnv coreutils jq tmux htop
    ];

    # === exo-process: start/stop/status EXO without needing sudo (PID/logs in $HOME) ===
    exoProcess = pkgs: pkgs.writeShellApplication {
      name = "exo-process";
      runtimeInputs = with pkgs; [ bash coreutils ];
      text = builtins.readFile ./fleet/lib/exo_process.sh;
    };

    mkHost = {
      hostName,
      userName,
      userEmail ? "toast@frenchtoastman.com",
      system   ? "aarch64-darwin",
      authorizedPubKeys ? [],
      extraAuthorizedKeys ? {}
    }:
      darwin.lib.darwinSystem {
        inherit system;
        modules = [
          home-manager.darwinModules.home-manager

          ({ pkgs, lib, ... }: {
            # ----- nix-darwin base -----
            system.stateVersion = 5;
            system.primaryUser  = userName;

            home-manager.useGlobalPkgs   = true;
            home-manager.useUserPackages = true;

            networking.hostName = hostName;

            # Determinate Nix is installed -> nix-darwin must NOT manage Nix itself
            nix.enable = false;

            programs.zsh.enable = true;
            environment.systemPackages =
              (commonPackages pkgs) ++ [
                (exoProcess pkgs)
              ];

            users.users.${userName} = {
              home = "/Users/${userName}";
              isHidden = false;
              shell = pkgs.zsh;
            };

            # ----- SSH (password login allowed) -----
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
                "pam.d/sudo_local".enable = lib.mkForce false;
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

            # Migrate common /etc files once
            system.activationScripts.migrateEtcBase.text = ''
              for f in /etc/nix/nix.conf /etc/bashrc /etc/zshrc; do
                if [ -e "$f" ] && [ ! -L "$f" ]; then
                  /bin/mv "$f" "$f.before-nix-darwin" || true
                fi
              done
            '';

            # Example tunable
            launchd.daemons."sysctl-tunables" = {
              command = ''${pkgs.bash}/bin/bash -lc '/usr/sbin/sysctl -w net.inet.tcp.msl=1000 || true' '';
              serviceConfig = { RunAtLoad = true; };
            };

            # ----- macOS defaults -----
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

            # ----- Home Manager (user) -----
            home-manager.backupFileExtension = "pre-hm";
            home-manager.users.${userName} = { pkgs, ... }: {
              home.stateVersion = "24.05";

              programs.git = {
                enable = true;
                settings = {
                  user = {
                    name = userName;
                    email = userEmail;
                  };
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
                  exo-dev = "nix develop -c uv run exo";
                };
                initContent = ''
                  if [ -f ~/.zshrc.before-nix ]; then
                    source ~/.zshrc.before-nix
                  fi
                  '';
                oh-my-zsh = {
                  enable = true;
                };
              };

              home.shellAliases = {
                exo-dev = "nix develop -c uv run exo";
              };
            };
          })

          # --- EXO modules you already use ---
          (import ./modules/exo-config-ip.nix)
          (import ./modules/exo-repo-sync.nix)
          (import ./modules/exo-gpu-wired-mem.nix)

          # --- Per-host overrides ---
          ({ lib, ... }: {
            launchd.daemons."exo-config-ip".serviceConfig.EnvironmentVariables = {
              WIFI_SERVICE = "Wi-Fi";
              LAN_PREFIX   = "192.168.1";
              NETMASK      = "255.255.255.0";
            };

            # Repo sync as user -> /opt/exo
            system.activationScripts.repoLogs.text = ''
              mkdir -p /Users/${userName}/Library/Logs
              chown ${userName}:staff /Users/${userName}/Library/Logs || true
            '';
            launchd.daemons."exo-repo-sync".serviceConfig = {
              UserName = userName;
              RunAtLoad = true;
              StartInterval = 900;
              StandardOutPath  = lib.mkForce "/Users/${userName}/Library/Logs/exo-repo-sync.log";
              StandardErrorPath = lib.mkForce "/Users/${userName}/Library/Logs/exo-repo-sync.err";
              EnvironmentVariables = {
                EXO_REPO_URL_SSH   = "git@github.com:exo-explore/exo.git";
                EXO_REPO_URL_HTTPS = "https://github.com/exo-explore/exo.git";
                EXO_REPO_BRANCH    = "main";
                EXO_REPO_DEST      = "/opt/exo";
                EXO_REPO_OWNER     = userName;
                EXO_DEPLOY_KEY     = "";
              };
            };

            # GPU wired memory sysctls (mac only)
            launchd.daemons."exo-gpu-wired-mem".serviceConfig.EnvironmentVariables = {
              WIRED_LIMIT_PERCENT = "90";
              WIRED_LWM_PERCENT   = "80";
            };
          })
        ];
      };

    # --- Linux (Ubuntu) Builder ---
    mkLinuxHost = {
      hostName,
      userName,
      userEmail ? "toast@frenchtoastman.com",
      system   ? "x86_64-linux",
      authorizedPubKeys ? [],
      extraAuthorizedKeys ? {}
    }:
      home-manager.lib.homeManagerConfiguration {
        pkgs = import nixpkgs { inherit system; };
        modules = [
          ({ pkgs, lib, ... }: {
            home.username = userName;
            home.homeDirectory = "/home/${userName}";
            home.stateVersion = "24.05";

            # --- Packages (parity with mkHost) ---
            home.packages =
              (commonPackages pkgs) ++ [
                (exoProcess pkgs)
              ] ++ (with pkgs; [
                cacert
                rustup
                nodejs
                pkg-config
                openssl
                gcc
              ]);

            # --- Shell (parity with mkHost) ---
            programs.zsh = {
              enable = true;
              shellAliases = {
                ll = "ls -lah";
                exo-dev = "nix develop -c uv run exo";
              };
              initExtra = ''
                if [ -f ~/.zshrc.before-nix ]; then
                  source ~/.zshrc.before-nix
                fi
              '';
              oh-my-zsh = {
                enable = true;
              };
            };

            programs.bash = {
              enable = true;
              initExtra = ''
                if [ -f ~/.bashrc.before-nix ]; then
                  source ~/.bashrc.before-nix
                fi
              '';
            };

            # --- Git (parity with mkHost) ---
            programs.git = {
              enable = true;
              settings = {
                user = {
                  name = userName;
                  email = userEmail;
                };
                pull.rebase = true;
                credential.helper = "store";
              };
            };

            programs.direnv = {
              enable = true;
              nix-direnv.enable = true;
            };

            # --- SSH Keys (parity with mkHost /etc/ssh/authorized_keys) ---
            home.activation.mergeAuthorizedKeys = lib.hm.dag.entryAfter ["writeBoundary"] ''
              keys_file="$HOME/.ssh/authorized_keys"
              backup_file="$HOME/.ssh/authorized_keys.before-nix"
              nix_keys="${lib.concatStringsSep "\n" authorizedPubKeys}"

              if [ -f "$keys_file" ] && [ ! -L "$keys_file" ] && [ ! -f "$backup_file" ]; then
                echo "Backing up existing authorized_keys to $backup_file"
                mv "$keys_file" "$backup_file"
              fi

              echo "# Generated by Nix (mkLinuxHost)" > "$keys_file.tmp"
              echo "$nix_keys" >> "$keys_file.tmp"

              if [ -f "$backup_file" ]; then
                echo "" >> "$keys_file.tmp"
                echo "# Merged from $backup_file" >> "$keys_file.tmp"
                cat "$backup_file" >> "$keys_file.tmp"
              fi
              mv "$keys_file.tmp" "$keys_file"
              chmod 600 "$keys_file"
            '';

            # --- Hostname (parity with networking.hostName) ---
            home.activation.setHostname = lib.hm.dag.entryAfter ["writeBoundary"] ''
              if command -v hostnamectl >/dev/null; then
                 CURRENT=$(hostnamectl --static 2>/dev/null || hostname)
                 if [ "$CURRENT" != "${hostName}" ]; then
                   $DRY_RUN_CMD sudo hostnamectl set-hostname "${hostName}" || true
                 fi
              fi
            '';
          })

          (import ./modules/exo-repo-sync-linux.nix)
        ];
      };

  in
  {
    # ===== Linux host config =====
    homeConfigurations."toast" = mkLinuxHost {
      hostName = "spark-f6cd";
      userName = "toast";
      userEmail = "toast@frenchtoastman.com";
      system   = "aarch64-linux";
      authorizedPubKeys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDDkE4dX1Zjtn6qnfsjh+5PoR3aJ/85RTeucPsBnBR7XdC85li1/lrxvrmSS73BCeay2TDV6BeBAfFvg9yFWsz8gDllKmA2yqiZzlSMSzzItoDCuErqrfca+z5Fiww85iL8q81CALeqb6F5kRRBCVqwreIioJMByHjzVNEjUH5iCOILNJD/rbVL/DkPO0uWxzoAdmlZCAyz8dCu667SwMtfnXXUjxLH714AyLwQw7lDrUCYT34iilBEN3GMpzw7ZaTob2MKxq9ww3zpDr5FuI7wHS6D8dsGQtovx+YwDbApUxe5bqaFOLrdIqv0nt5WHpOqTG68rzK5yiXJh3+QW+uyI7AwavvVoT86INCm23a6DjeLjXvm7nSCFJEAbdN3+a5GXufqFMuB74zt6blDrew1DxkUnkJSTsi/CBjZmBCJdINm+IU1qhwsH0gFgXqrPIpT0Kei8Ul3XvEXGVljd2yrmbuZ0jg3NeGhSMnJf24iSxWwIflK8NUrDvzTmmxcftU="
      ];
    };

    # ===== macOS host config =====
    darwinConfigurations."toast" = mkHost {
      hostName = "jeeves-studio-1";
      userName = "toast";
      userEmail = "toast@frenchtoastman.com";
      system   = "aarch64-darwin";
      authorizedPubKeys = [
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDDkE4dX1Zjtn6qnfsjh+5PoR3aJ/85RTeucPsBnBR7XdC85li1/lrxvrmSS73BCeay2TDV6BeBAfFvg9yFWsz8gDllKmA2yqiZzlSMSzzItoDCuErqrfca+z5Fiww85iL8q81CALeqb6F5kRRBCVqwreIioJMByHjzVNEjUH5iCOILNJD/rbVL/DkPO0uWxzoAdmlZCAyz8dCu667SwMtfnXXUjxLH714AyLwQw7lDrUCYT34iilBEN3GMpzw7ZaTob2MKxq9ww3zpDr5FuI7wHS6D8dsGQtovx+YwDbApUxe5bqaFOLrdIqv0nt5WHpOqTG68rzK5yiXJh3+QW+uyI7AwavvVoT86INCm23a6DjeLjXvm7nSCFJEAbdN3+a5GXufqFMuB74zt6blDrew1DxkUnkJSTsi/CBjZmBCJdINm+IU1qhwsH0gFgXqrPIpT0Kei8Ul3XvEXGVljd2yrmbuZ0jg3NeGhSMnJf24iSxWwIflK8NUrDvzTmmxcftU="
      ];
    };
  };
}

