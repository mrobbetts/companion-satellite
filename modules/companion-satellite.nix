{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.companion-satellite;
in
{
  options.services.companion-satellite = {
    enable = lib.mkEnableOption "Companion Satellite, a network connector for Stream Decks and other surfaces to Bitfocus Companion";

    package = lib.mkOption {
      type = lib.types.package;
      description = "The companion-satellite package to use.";
      # Default is set by the flake's nixosModule wrapper; when importing this
      # file directly, either set this option or add the flake's overlay:
      default = pkgs.companion-satellite;
      defaultText = lib.literalExpression "pkgs.companion-satellite";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Open the REST/web UI port (see {option}`services.companion-satellite.restPort`)
        and UDP 5353 for mDNS announcement (lets Companion auto-discover this satellite).
        The outgoing connection to Companion (TCP 16622) needs no firewall rule.
      '';
    };

    restPort = lib.mkOption {
      type = lib.types.port;
      default = 9999;
      description = ''
        Port of the REST API / configuration web UI, used only for
        {option}`openFirewall`. The actual port is set in Satellite's own
        config (web UI or `/var/lib/companion-satellite/config.json`) and
        defaults to 9999; keep the two in sync if you change it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # The bundled udev rules grant the supported USB/HID surfaces to this
    # group (upstream's pi-image does the same with a 'satellite' user).
    users.groups.satellite = { };
    services.udev.packages = [ cfg.package ];

    systemd.services.companion-satellite = {
      description = "Bitfocus Companion Satellite";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${lib.getExe cfg.package} %S/companion-satellite/config.json";
        DynamicUser = true;
        StateDirectory = "companion-satellite";
        SupplementaryGroups = [
          "satellite" # hidraw/USB access via the bundled udev rules
          "input" # SUBSYSTEM=="input" devices (some surfaces)
        ];
        Environment = [ "HOME=%S/companion-satellite" ];
        # match upstream's satellite.service
        Restart = "on-failure";
        KillSignal = "SIGINT";
        TimeoutStopSec = 60;
      };
    };

    networking.firewall = lib.mkIf cfg.openFirewall {
      allowedTCPPorts = [ cfg.restPort ];
      allowedUDPPorts = [ 5353 ]; # mDNS discovery
    };
  };
}
