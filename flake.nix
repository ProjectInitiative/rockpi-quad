{
  description = "Nix package for Rockpi Quad SATA Hat Controller";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, nixos-hardware, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        py3 = pkgs.python3; # Use specific version if needed, e.g., pkgs.python311
        pythonPackages = py3.pkgs;

        # Define Python dependencies based on requirements.txt
        pythonDeps = with pythonPackages; [
          adafruit-blinka
          adafruit-circuitpython-busdevice
          adafruit-circuitpython-connectionmanager
          adafruit-circuitpython-framebuf
          adafruit-circuitpython-requests
          adafruit-circuitpython-ssd1306
          adafruit-circuitpython-typing
          adafruit-platformdetect
          adafruit-pureio
          libgpiod # Provides the python bindings
          pillow
          psutil
          pyftdi
          pyserial
          python-periphery
          pyusb
          raspberrypilib # For RPi.GPIO, might be optional if Blinka handles all
          spidev
          sysv-ipc
        ];

        # Main package derivation
        rockpi-quad-pkg = pythonPackages.buildPythonApplication {
          pname = "rockpi-quad";
          version = "0.3.1"; # From DEBIAN/control

          src = ./.; # Assumes flake.nix is in the quad-hat directory

          format = "other"; # Not a standard python package structure

          propagatedBuildInputs = pythonDeps;

          # We need patchShebangs for the python scripts
          nativeBuildInputs = [ pkgs.patchelf ];

          installPhase = ''
            runHook preInstall

            install_dir=$out/bin/rockpi-quad
            mkdir -p $install_dir $out/etc $out/share/fonts/rockpi-quad

            # Copy Python application code
            cp -r $src/rockpi-quad/usr/bin/rockpi-quad/* $install_dir/

            # Copy default config and RPi4 env file
            cp $src/rockpi-quad/etc/rockpi-quad.conf.txt $out/etc/rockpi-quad.conf.default
            cp $src/rockpi-quad/usr/bin/rockpi-quad/env/rpi4.env.txt $out/etc/rockpi-quad.env.rpi4

            # Fix hardcoded config path in misc.py
            substituteInPlace $install_dir/misc.py \
              --replace "'/etc/rockpi-penta.conf'" "'/etc/rockpi-quad.conf'"

            # Make main script executable
            chmod +x $install_dir/main.py

            # Patch shebangs
            patchShebangs $install_dir

            runHook postInstall
          '';

          meta = with pkgs.lib; {
            description = "Rockpi Quad SATA Hat Controller";
            homepage = "https://github.com/radxa/rockpi-quad";
            license = licenses.mit; # From LICENSE.txt
            maintainers = [ maintainers.none ]; # Add your handle if you maintain this
            platforms = platforms.linux; # Specifically tested for RPi
          };
        };

        # NixOS Module
        nixosModule = { config, lib, pkgs, ... }:
          let
            cfg = config.hardware.rockpi-quad;
          in
          {
            imports = [
              # Import necessary RPi hardware modules
              nixos-hardware.nixosModules.raspberry-pi-4
            ];

            options.hardware.rockpi-quad = {
              enable = lib.mkEnableOption "Enable the Rockpi Quad SATA Hat service";

              package = lib.mkOption {
                type = lib.types.package;
                default = rockpi-quad-pkg;
                defaultText = lib.literalExpression "pkgs.rockpi-quad";
                description = "Package providing the Rockpi Quad SATA Hat software.";
              };

              user = lib.mkOption {
                type = lib.types.str;
                default = "rockpi-quad";
                description = "User to run the service as.";
              };

              group = lib.mkOption {
                type = lib.types.str;
                default = "rockpi-quad";
                description = "Group to run the service as.";
              };

              configFile = lib.mkOption {
                type = lib.types.path;
                default = "/etc/rockpi-quad.conf";
                description = "Path to the configuration file.";
              };

              # Add options mirroring the .conf file if desired
              settings = lib.mkOption {
                type = lib.types.attrs; # Or use types.submodule for structured options
                default = {};
                description = "Settings for rockpi-quad.conf. Merged with defaults.";
                example = {
                  fan.lv0 = 38;
                  key.press = "reboot";
                  oled."f-temp" = true;
                };
              };
            };

            config = lib.mkIf cfg.enable {
              environment.systemPackages = [ cfg.package pkgs.python3 ];

              # Enable necessary hardware interfaces for RPi4
              hardware.raspberry-pi."4".i2c1.enable = true; # For OLED (assuming standard pins)
              hardware.raspberry-pi."4".pwm.enable = true; # For Fan PWM (assuming standard pins)

              # GPIO Access Setup
              users.groups.gpio = lib.mkDefault {}; # Ensure gpio group exists
              users.groups.${cfg.group} = {};
              users.users.${cfg.user} = {
                isSystemUser = true;
                group = cfg.group;
                extraGroups = [ "gpio" "i2c" "pwm" ]; # Add necessary groups
              };

              # Udev rule to grant GPIO access (adapt if needed)
              services.udev.extraRules = lib.mkDefault ''
                SUBSYSTEM=="bcm2835-gpiomem", KERNEL=="gpiomem", GROUP="${cfg.group}", MODE="0660"
                SUBSYSTEM=="gpio", KERNEL=="gpiochip*", ACTION=="add", RUN+="${pkgs.bash}/bin/bash -c 'chown root:${cfg.group} /sys/class/gpio/export /sys/class/gpio/unexport ; chmod 220 /sys/class/gpio/export /sys/class/gpio/unexport'"
                SUBSYSTEM=="gpio", KERNEL=="gpio*", ACTION=="add", RUN+="${pkgs.bash}/bin/bash -c 'chown root:${cfg.group} /sys/%p/active_low /sys/%p/direction /sys/%p/edge /sys/%p/value ; chmod 660 /sys/%p/active_low /sys/%p/direction /sys/%p/edge /sys%p/value'"
              '';

              # Generate config file
              environment.etc."rockpi-quad.conf" = {
                source = pkgs.writeText "rockpi-quad.conf" (
                  lib.generators.toINI {} (
                    lib.recursiveUpdate {
                      # Default settings can be placed here or read from the default file
                      fan = { lv0 = 35; lv1 = 40; lv2 = 45; lv3 = 50; };
                      key = { click = "slider"; twice = "switch"; press = "none"; };
                      time = { twice = 0.7; press = 1.8; };
                      slider = { auto = true; time = 10; };
                      oled = { rotate = false; "f-temp" = false; };
                    } cfg.settings
                  )
                );
                mode = "0644";
              };

              # Generate environment file for the service
              environment.etc."rockpi-quad.env".source = "${cfg.package}/etc/rockpi-quad.env.rpi4";

              # Systemd Service Definition
              systemd.services.rockpi-quad = {
                description = "Rockpi Quad SATA Hat Controller";
                wantedBy = [ "multi-user.target" ];
                after = [ "network.target" ]; # Add dependencies if needed

                serviceConfig = {
                  User = cfg.user;
                  Group = cfg.group;
                  ExecStart = "${pkgs.python3}/bin/python3 ${cfg.package}/bin/rockpi-quad/main.py";
                  KillSignal = "SIGINT";
                  EnvironmentFile = "/etc/rockpi-quad.env";
                  Restart = "on-failure";
                  WorkingDirectory = "${cfg.package}/bin/rockpi-quad";
                  # Add sandboxing/hardening options if desired
                  # ProtectSystem = "strict";
                  # ProtectHome = true;
                  # DeviceAllow = [ "/dev/i2c-1 rw" "/dev/gpiomem rw" "/dev/gpiochip0 rw" "/dev/pwmchip0 rw" ]; # Adjust devices as needed
                  # AmbientCapabilities = [ "CAP_SYS_RAWIO" ]; # May be needed for GPIO/PWM
                };
              };
            };
          };

      in {
        packages.rockpi-quad = rockpi-quad-pkg;
        nixosModules.rockpi-quad = nixosModule;
        # Make the package easily accessible via legacyPackages for non-flake users
        legacyPackages.rockpi-quad = rockpi-quad-pkg;
      }
    );
}
