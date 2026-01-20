{ pkgs,
  lib ? pkgs.lib,
  stdenv ? pkgs.stdenv,
  toolchain-bin  ## provided by nixpkgs-genode
}: 

stdenv.mkDerivation rec {
    name = "goa";
    version = "2024-11-04";

    src = ./.;

    buildInputs = with pkgs; [
      expect
      
      ## dependencies documented at https://github.com/genodelabs/goa/blob/master/bin/goa#L42
      git gnumake wget findutils gnused diffutils gnutar libxml2.bin

      ## dependencies for `goa help`
      man less

      ## https://github.com/genodelabs/goa/blob/master/share/goa/lib/actions/build.tcl#L152
      toolchain-bin
    ];

    nativeBuildInputs = with pkgs; [
      makeWrapper
      gnused
      autoPatchelfHook
    ];

    installPhase = ''
        mkdir -p $out
        cp -r ./* $out

        wrapProgram $out/bin/goa --set PATH "${lib.makeBinPath buildInputs}:$PATH"

        ## substitute hardcoded paths of genode-toolchain
        sed -e 's@^set genode_tools_dir.*$@set genode_tools_dir "${toolchain-bin}/bin/"@' -i $out/share/goa/lib/backtrace
        sed -e 's@set qt_tool_dir.*$@set qt_tool_dir "${toolchain-bin}/"@' -i $out/share/goa/lib/build/qmake.tcl  ## TODO test
        sed -e 's@arm_v8a { set cross_dev_prefix.*$@arm_v8a { set cross_dev_prefix "${toolchain-bin}/bin/genode-aarch64-" }@' -i $out/share/goa/lib/command_line.tcl
        sed -e 's@x86_64 *{ set cross_dev_prefix.*$@x86_64 { set cross_dev_prefix "${toolchain-bin}/bin/genode-x86-" }@' -i $out/share/goa/lib/command_line.tcl
    '';
}
