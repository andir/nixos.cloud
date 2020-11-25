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
          pkgs = import nixpkgs {
            inherit system;
            overlays = [
              (self: super: {
              })
            ];
          };
        in
        lib.nameValuePair system (if pattern != null then extract (func pkgs) pattern else func pkgs)
      )
      archs);
  images = {
    amazon = mkImage "*.vhd" [ "x86_64-linux" "aarch64-linux" ] (pkgs: (pkgs.nixos {
      imports = [
        (pkgs.path + "/nixos/maintainers/scripts/ec2/amazon-image.nix")
      ];
    }).amazonImage);

    openstack = mkImage "*.qcow2" [ "x86_64-linux" ] (pkgs: (pkgs.nixos {
      imports = [
        (pkgs.path + "/nixos/maintainers/scripts/openstack/openstack-image.nix")
      ];
    }).openstackImage);

    kexec = mkImage null [ "x86_64-linux" ] (pkgs: let
      b = pkgs.callPackage (sources.nixos-generators + "/nixos-generate.nix") {
        nixpkgs = pkgs.path;
        inherit (pkgs) system;
        configuration = {
          imports = [
            # FIXME: add cloud-init metadata fetcher?
          ];
        };
        formatConfig = import (sources.nixos-generators + "/formats/kexec-bundle.nix");
      };
    in b.config.system.build.kexec_bundle);
  };

  attributes = lib.flatten
    (map
      (imageName: map
        (arch:
          lib.nameValuePair "${imageName}-${arch}" images.${imageName}.${arch})
        (builtins.attrNames images.${imageName}))
      (builtins.attrNames images));

in
rec {
  inherit images;

  build = buildPkgs.runCommand "build-images"
    {
      outputs = [ "out" "listing" ];
    } ''
    mkdir $out
    ${lib.concatMapStringsSep "\n"
      (target: "ln -s ${target.value} $out/${target.name}")
    attributes}
    cd $out && find -L . -type f | sed -e "s;^\./;;" > $listing
  '';

  site = buildPkgs.runCommand "site"
    {
      buildInputs = [ buildPkgs.pandoc ];

      markdownDocument = buildPkgs.substituteAll {
        name = "markdown";
        src = ./index.md;
        nixpkgsRevision = nixpkgs.rev;
        imagesMarkdown = lib.concatMapStringsSep "\n"
          (file:
            ''
              - [${file}](images/${file})
            ''
          )
          (builtins.filter (x: x != [ ] && x != "") (builtins.split "\n" (builtins.readFile build.listing)));
      };
    } ''
    mkdir $out
    pandoc -f markdown -t html -o $out/index.html $markdownDocument
    ln -s ${build} $out/images
  '';

  shell = buildPkgs.mkShell {
    buildInputs = [
      buildPkgs.netlify-cli
      buildPkgs.nix
      buildPkgs.bash
    ];
  };
}
