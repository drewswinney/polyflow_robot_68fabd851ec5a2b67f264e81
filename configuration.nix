{ config, pkgs, ros-pkgs, lib, ... }:

let
  user = "admin";
  password = "password";
  interface = "end0";
  hostname = "68fabd851ec5a2b67f264e81";
in {
  nixpkgs.overlays = [
    (final: super: {
      makeModulesClosure = x:
        super.makeModulesClosure (x // { allowMissing = true; });
    })
  ];

  imports = [
     "${builtins.fetchGit { url = "https://github.com/NixOS/nixos-hardware.git"; rev="26ed7a0d4b8741fe1ef1ee6fa64453ca056ce113"; }}/raspberry-pi/4"
  ];
  
  boot = {
    kernelPackages = ros-pkgs.linuxKernel.packages.linux_rpi4;
    initrd.availableKernelModules = [ "xhci_pci" "usbhid" "usb_storage" ];
    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };
  };

  fileSystems = {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
      options = [ "noatime" ];
    };
  };

  system.autoUpgrade.flags = ["--max-jobs" "1" "--cores" "1"];

  networking = {
    hostName = "68fabd851ec5a2b67f264e81";
    networkmanager.enable = true;
    nftables.enable = true;
  };

  environment.etc."nixos/configuration.nix" = {
    source = ./configuration.nix;
    mode = "0644";
  };

  environment.systemPackages = with ros-pkgs; with rosPackages.humble; [ vim git wget inetutils ros-base ros-core gh python3 python3Packages.pip colcon ros2cli ];

  services.openssh.enable = true;

  users = {
    mutableUsers = false;
    users."${user}" = {
      isNormalUser = true;
      password = password;
      extraGroups = [ "wheel" ];
    };
  };

  # Services
  systemd.services.polyflow_startup = {
    description = "Clone the robot git repository and start ROS";
    wantedBy = [ "multi-user.target" ]; # Or a more specific target if needed
    unitConfig = {
      After = [ "network-online.target" "time-sync.target" ];
      Wants = [ "network-online.target" "time-sync.target" ];
    };
    serviceConfig = {
      Type = "oneshot";
      User = "admin";
      Group = "users";
      ExecStart = "${ros-pkgs.writeShellScript "clone-repo" ''
      export HOME=/home/${user}
      DIRECTORY="/home/${user}/polyflow_robot_68fabd851ec5a2b67f264e81"
      if [[ -d "$DIRECTORY" ]];
        then
          cd "$DIRECTORY"
          ${ros-pkgs.git}/bin/git pull
        else
          cd /home/${user}
          ${ros-pkgs.git}/bin/git config --global --unset https.proxy
          ${ros-pkgs.git}/bin/git clone https://github.com/drewswinney/polyflow_robot_68fabd851ec5a2b67f264e81.git
          chown -R ${user}:users /home/${user}/polyflow_robot_68fabd851ec5a2b67f264e81

          cd /home/${user}/polyflow_robot_68fabd851ec5a2b67f264e81/workspace
          ${ros-pkgs.colcon}/bin/colcon build --packages-select webrtc
          source install/setup.bash
          cd src/webrtc

          ${ros-pkgs.rosPackages.humble.ros2cli}/bin/ros2 launch webrtc launch/webrtc.launch.py
        fi
      ''}";
      StandardError = "inherit"; # Merges stderr with stdout
    };
  };

  services.timesyncd.enable = true;
  services.timesyncd.servers = [ "pool.ntp.org" ];
  systemd.additionalUpstreamSystemUnits = [ "systemd-time-wait-sync.service" ];
  systemd.services.systemd-time-wait-sync.wantedBy = [ "multi-user.target" ];

  nix.settings.experimental-features = ["nix-command" "flakes" ];

  hardware.enableRedistributableFirmware = true;
  system.stateVersion = "23.11";
}