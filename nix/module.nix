{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.omdrop-owl;
  ifaces = [
    "awdl0"
    "mon0"
    "awdlibss0"
  ];
in
{
  options.services.omdrop-owl = {
    enable = lib.mkEnableOption "omdrop-owl, the AirDrop radio backend for omdrop";

    # With the system's NetworkManager: an nmcli newer than the daemon can't
    # release the station ("No such method SetManaged"), and NetworkManager
    # then takes it back in the middle of an exclusive window.
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ./package.nix {
        networkmanager = config.networking.networkmanager.package;
      };
      defaultText = lib.literalExpression ''
        pkgs.callPackage ./package.nix {
          networkmanager = config.networking.networkmanager.package;
        }
      '';
      description = "The omdrop-owl package to use.";
    };

    interface = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "wlp0s20f0u1";
      description = "Wi-Fi interface to run AirDrop on (/etc/omdrop/infra-iface). Default: the first managed one.";
    };

    allowUntested = lib.mkEnableOption "cards whose profile is untested (/etc/omdrop/allow-untested)";

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Open omdrop's receiver port, TCP 8771, on awdl0.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
    security.polkit.enable = true;
    hardware.bluetooth.enable = lib.mkDefault true;

    networking.networkmanager.unmanaged = map (i: "interface-name:${i}") ifaces;
    networking.firewall.interfaces.awdl0.allowedTCPPorts = lib.mkIf cfg.openFirewall [ 8771 ];

    # packaging/10-omdrop-owl-awdl0.link: udev must not give awdl0 a MAC
    # address of its own, or omdrop announces a link-local awdl0 doesn't have.
    systemd.network.links."10-omdrop-owl-awdl0" = {
      matchConfig.OriginalName = "awdl0";
      linkConfig.MACAddressPolicy = "none";
    };

    # NixOS restarts wpa_supplicant whenever a Wi-Fi interface comes or goes,
    # which drops the connection each time OWL's monitor interface does.
    services.udev.packages = [
      (pkgs.writeTextDir "lib/udev/rules.d/00-omdrop-owl.rules" ''
        SUBSYSTEM=="net", KERNEL=="${lib.concatStringsSep "|" ifaces}", RUN:="${pkgs.coreutils}/bin/true"
      '')
    ];

    environment.etc = {
      "omdrop/infra-iface" = lib.mkIf (cfg.interface != null) { text = cfg.interface + "\n"; };
      "omdrop/allow-untested" = lib.mkIf cfg.allowUntested { text = "1\n"; };
    };
  };
}
