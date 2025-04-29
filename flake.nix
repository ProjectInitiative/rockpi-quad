{
  description = "Nix package for Rockpi Quad SATA Hat Controller";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-hardware.url = "github:NixOS/nixos-hardware";
    # flake-utils is removed
  };

  outputs = { self, nixpkgs,  nixos-hardware }:
    let
      system = "aarch64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      lib = pkgs.lib;

      packageOverrides = pkgs.callPackage ./python-packages.nix {};
      python = pkgs.python3.override { inherit packageOverrides; };


      # Define Python dependencies as a list using the final package set
      pythonDeps = [
      (python.withPackages(p: [
          p.Adafruit-Blinka
          p.adafruit-circuitpython-busdevice
          p.adafruit-circuitpython-connectionmanager
          p.adafruit-circuitpython-framebuf
          p.adafruit-circuitpython-requests
          p.adafruit-circuitpython-ssd1306
          p.adafruit-circuitpython-typing
          p.Adafruit-PlatformDetect
          p.Adafruit-PureIO
          p.libgpiod # Assuming from base nixpkgs
          p.pillow # Assuming from base nixpkgs
          p.psutil # Assuming from base nixpkgs
          p.pyftdi
          p.pyserial
          p.python-periphery # Assuming from base nixpkgs
          p.pyusb
          p.raspberrypilib # Assuming from base nixpkgs
          p.spidev # Assuming from base nixpkgs
          p.sysv-ipc # Assuming from base nixpkgs
        ]))
      ];

      # Main package derivation
      rockpi-quad-pkg = pkgs.python3Packages.buildPythonApplication {
        pname = "rockpi-quad";
        version = "0.3.1";

        src = ./.;

        format = "other";

        propagatedBuildInputs = pythonDeps;
        nativeBuildInputs = [ pkgs.patchelf ];

        installPhase = ''
          runHook preInstall

          install_dir=$out/bin/rockpi-quad
          mkdir -p $install_dir $out/etc $out/share/fonts/rockpi-quad

          cp -r $src/rockpi-quad/usr/bin/rockpi-quad/* $install_dir/
          cp $src/rockpi-quad/etc/rockpi-quad.conf.txt $out/etc/rockpi-quad.conf.default
          cp $src/rockpi-quad/usr/bin/rockpi-quad/env/rpi4.env.txt $out/etc/rockpi-quad.env.rpi4

          substituteInPlace $install_dir/misc.py \
            --replace "'/etc/rockpi-penta.conf'" "'/etc/rockpi-quad.conf'"

          chmod +x $install_dir/main.py
          patchShebangs $install_dir

          runHook postInstall
        '';

        meta = {
          description = "Rockpi Quad SATA Hat Controller";
          homepage = "https://github.com/radxa/rockpi-quad";
          license = lib.licenses.mit;
          maintainers = [ lib.maintainers.none ];
          platforms = lib.platforms.linux; # Specifically aarch64-linux
        };
      };

      # NixOS Module definition (remains mostly the same)
      nixosModule = { config, lib, pkgs, ... }:
        let
          cfg = config.hardware.rockpi-quad;
        in
        {

          options.hardware.rockpi-quad = {
            enable = lib.mkEnableOption "Enable the Rockpi Quad SATA Hat service";

            package = lib.mkOption {
              type = lib.types.package;
              # Default now refers directly to the package defined above
              default = rockpi-quad-pkg;
              defaultText = lib.literalExpression "config.flake.packages.rockpi-quad"; # Example text
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

            settings = lib.mkOption {
              type = lib.types.attrs;
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

            users.groups.gpio = lib.mkDefault {};
            users.groups.${cfg.group} = {};
            users.users.${cfg.user} = {
              isSystemUser = true;
              group = cfg.group;
              extraGroups = [ "gpio" "i2c" "pwm" ];
            };

            services.udev.extraRules = lib.mkDefault ''
              SUBSYSTEM=="bcm2835-gpiomem", KERNEL=="gpiomem", GROUP="${cfg.group}", MODE="0660"
              SUBSYSTEM=="gpio", KERNEL=="gpiochip*", ACTION=="add", RUN+="${pkgs.bash}/bin/bash -c 'chown root:${cfg.group} /sys/class/gpio/export /sys/class/gpio/unexport ; chmod 220 /sys/class/gpio/export /sys/class/gpio/unexport'"
              SUBSYSTEM=="gpio", KERNEL=="gpio*", ACTION=="add", RUN+="${pkgs.bash}/bin/bash -c 'chown root:${cfg.group} /sys/%p/active_low /sys/%p/direction /sys/%p/edge /sys/%p/value ; chmod 660 /sys/%p/active_low /sys/%p/direction /sys/%p/edge /sys%p/value'"
            '';

            environment.etc."rockpi-quad.conf" = {
              source = pkgs.writeText "rockpi-quad.conf" (
                lib.generators.toINI {} (
                  lib.recursiveUpdate {
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

            environment.etc."rockpi-quad.env".source = "${cfg.package}/etc/rockpi-quad.env.rpi4";

            systemd.services.rockpi-quad = {
              description = "Rockpi Quad SATA Hat Controller";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];

              serviceConfig = {
                User = cfg.user;
                Group = cfg.group;
                ExecStart = "${pkgs.python3}/bin/python3 ${cfg.package}/bin/rockpi-quad/main.py";
                KillSignal = "SIGINT";
                EnvironmentFile = "/etc/rockpi-quad.env";
                Restart = "on-failure";
                WorkingDirectory = "${cfg.package}/bin/rockpi-quad";
              };
            };
          };
        };

    in {
      # Expose outputs directly
      packages.${system}.rockpi-quad = rockpi-quad-pkg; # Keep arch-specific packages structure
      nixosModules.rockpi-quad = nixosModule;           # Module is generic

      # Add legacyPackages for convenience if needed by non-flake tooling
      legacyPackages.${system}.rockpi-quad = rockpi-quad-pkg;
    };
}
