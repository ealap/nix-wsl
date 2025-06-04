{ config, pkgs, lib, ... }:
with builtins; with lib;
let
  cfg = config.wsl.tarball;

  icon = ../assets/NixOS-WSL.ico;
  iconPath = "/etc/nixos.ico";

  wsl-distribution-conf = pkgs.writeText "wsl-distribution.conf" (
    generators.toINI { } {
      oobe.defaultName = "NixOS";
      shortcut.icon = iconPath;
    }
  );

  nixosWslBranch =
    let
      # Use the nix parser conveniently built into nix
      flake = import ../flake.nix;
      url = flake.inputs.nixpkgs.url;
      version = lib.removePrefix "github:NixOS/nixpkgs/nixos-" url;
    in
    if version == "unstable"
    then "main"
    else "release-" + version;

  defaultConfig = pkgs.writeText "default-configuration.nix" ''
    { config, lib, pkgs, ... }:

    {
      imports = [ <nixos-wsl/modules> ];

      nix.settings.experimental-features = [
        "flakes"
        "nix-command"
      ];

      wsl.enable = true;
      wsl.defaultUser = "${config.wsl.defaultUser}";
      wsl.defaultUser = "ealap";
      wsl.wslConf.network.hostname = "nixos";

      system.stateVersion = "${config.system.nixos.release}";
    }
  '';
in
{
  options.wsl.tarball = {
    configPath = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Path to system configuration which is copied into the tarball";
    };
  };

  # These options make no sense without the wsl-distro module anyway
  config = mkIf config.wsl.enable {
    system.build.tarballBuilder = pkgs.writeShellApplication {
      name = "nixos-wsl-tarball-builder";

      runtimeInputs = [
        pkgs.coreutils
        pkgs.e2fsprogs
        pkgs.gnutar
        pkgs.nixos-install-tools
        pkgs.pigz
        config.nix.package
      ];

      text = ''
        if ! [ $EUID -eq 0 ]; then
          echo "This script must be run as root!"
          exit 1
        fi

        # Use .wsl extension to support double-click installs on recent versions of Windows
        out=''${1:-nixos.wsl}

        root=$(mktemp -p "''${TMPDIR:-/tmp}" -d nixos-wsl-tarball.XXXXXXXXXX)
        # FIXME: fails in CI for some reason, but we don't really care because it's CI
        trap 'chattr -Rf -i "$root" || true && rm -rf "$root" || true' INT TERM EXIT

        chmod o+rx "$root"

        echo "[NixOS-WSL] Installing..."
        nixos-install \
          --root "$root" \
          --no-root-passwd \
          --system ${config.system.build.toplevel} \
          --substituters ""

        echo "[NixOS-WSL] Adding channel..."
        nixos-enter --root "$root" --command 'HOME=/root nix-channel --add https://github.com/nix-community/NixOS-WSL/archive/refs/heads/${nixosWslBranch}.tar.gz nixos-wsl'
        nixos-enter --root "$root" --command 'HOME=/root nix-channel --add https://nixos.org/channels/nixos-unstable nixos'
        nixos-enter --root "$root" --command 'HOME=/root nix-channel --add https://github.com/nix-community/NixOS-WSL/archive/refs/heads/main.tar.gz nixos-wsl'

        echo "[NixOS-WSL] Adding wsl-distribution.conf"
        install -Dm644 ${wsl-distribution-conf} "$root/etc/wsl-distribution.conf"
        install -Dm644 ${icon} "$root${iconPath}"

        echo "[NixOS-WSL] Adding default config..."
        ${if cfg.configPath == null then ''
          install -Dm644 ${defaultConfig} "$root/etc/nixos/configuration.nix"
        '' else ''
          mkdir -p "$root/etc/nixos"
          cp -R ${lib.cleanSource cfg.configPath}/. "$root/etc/nixos"
          chmod -R u+w "$root/etc/nixos"
        ''}

        echo "[NixOS-WSL] Compressing..."
        tar -C "$root" \
          -c \
          --sort=name \
          --mtime='@1' \
          --owner=0 \
          --group=0 \
          --numeric-owner \
          --hard-dereference \
          . \
        | pigz > "$out"
      '';
    };
  };
}
