let
  sources = import ./nix/sources.nix;
  nixpkgs = sources.nixpkgs;

  buildPkgs = import nixpkgs { };

  inherit (buildPkgs) lib;

  extract = image: pattern: buildPkgs.runCommand "extracted" { inherit image pattern; } ''
    set -e
    mkdir $out
    ln -s $image/$pattern $out
  '';

  mkImage = pattern: archs: func:
    lib.listToAttrs (map
      (system:
        let
          pkgs = import nixpkgs { inherit system; };
        in
        lib.nameValuePair system (extract (func pkgs) pattern)
      )
      archs);
in
rec {
  images = {
    amazon = mkImage "*.vhd" [ "x86_64-linux" ] (pkgs: (pkgs.nixos {
      imports = [
        (pkgs.path + "/nixos/maintainers/scripts/ec2/amazon-image.nix")
      ];
    }).amazonImage);

    openstack = mkImage "*.qcow2" [ "x86_64-linux" ] (pkgs: (pkgs.nixos {
      imports = [
        (pkgs.path + "/nixos/maintainers/scripts/openstack/openstack-image.nix")
      ];
    }).openstackImage);
  };

  script =
    let
      path = buildPkgs.buildEnv {
        name = "builder-env";
        paths = [ buildPkgs.nix buildPkgs.coreutils ];
      };

      attributes = lib.flatten
        (map (imageName: map (arch: lib.nameValuePair "${imageName}-${arch}" (lib.concatStringsSep "." [ imageName arch ])) (builtins.attrNames images.${imageName})) (builtins.attrNames images));

    in
    buildPkgs.writeShellScript "build-images" ''
      PATH=${path}/bin
      ${lib.concatMapStringsSep "\n"
        (target: "nix-build ${./.}/images.nix -A images.${target.value} -o ${target.name}")
      attributes
      }
    '';

  shell = buildPkgs.mkShell { };
}
