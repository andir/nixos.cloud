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

  build =
    let
      attributes = lib.flatten
        (map
          (imageName: map
            (arch:
              lib.nameValuePair "${imageName}-${arch}" images.${imageName}.${arch})
            (builtins.attrNames images.${imageName}))
          (builtins.attrNames images));
    in
    buildPkgs.runCommand "build-images" { } ''
      mkdir $out
      ${lib.concatMapStringsSep "\n"
        (target: "ln -s ${target.value} $out/${target.name}")
      attributes}
    '';
}
