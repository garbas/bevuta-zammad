{ pkgs }:

with import (pkgs.path + "/nixos/lib/testing-python.nix") {
  inherit pkgs;
  system = pkgs.system;
};
with pkgs.lib;

makeTest {

  machine = { config, pkgs, ... }: {
    imports = [ ./nixos_module.nix ];
    nixpkgs.overlays = [ (import ./overlay.nix) ];
    services.zammad.enable = true;
    services.zammad.secretsFile = "${./test_secrets}";
  };

  testScript = ''
    start_all()
    machine.wait_for_unit("postgresql.service")
    machine.wait_for_unit("zammad-web.service")
    machine.wait_for_unit("zammad-websocket.service")
    machine.wait_for_unit("zammad-scheduler.service")

    # without the grep the command does not produce valid utf-8 for some reason
    with subtest("welcome screen loads"):
        machine.succeed(
            "curl -sSfL http://localhost:3000/ | grep '<title>Zammad'"
        )
  '';
}
