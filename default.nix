let
  rev = "nixos-unstable";
in
{ pkgs ? import (builtins.fetchTarball "https://github.com/NixOS/nixpkgs/archive/${rev}.tar.gz") {}
}:

{
  zammad = pkgs.callPackage ./zammad {
    ruby = pkgs.ruby_2_6;
  };
}
