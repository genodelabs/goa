{
  description = ''
    This flake provides `goa` with the required dependencies from [nixpkgs](https://nixos.org/).

    The `goa`-executable can be used without installation:
    ```sh
    nix run github:johannesloetzsch/goa -- help
    ```

    The `defaultShell` opens an environment with `goa`, its dependencies and the `genode-toolchain`.
    Usage:
    ```sh
    nix shell github:johannesloetzsch/goa
    goa help
    ```
  '';

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-23.11";

    flake-compat = {
      url = "github:edolstra/flake-compat";
      flake = false;
    };

    genode-utils = {
      url = "github:zgzollers/nixpkgs-genode";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, flake-compat, genode-utils }:
  let
    inherit (genode-utils.packages.${system}) toolchain-bin;

    system = "x86_64-linux";
    pkgs = import nixpkgs { inherit system; };
  in rec {
    packages.${system} = rec {

      ## The [Genode tool chain](https://genode.org/download/tool-chain)
      ## provided by [nixpkgs-genode](https://github.com/zgzollers/nixpkgs-genode/blob/main/pkgs/toolchain-bin.nix)
      inherit toolchain-bin;

      goa = import ./default.nix { inherit pkgs toolchain-bin; };
      default = goa;
    };

    defaultShell = pkgs.mkShell {
      buildInputs = with packages.${system}; [ goa goa.buildInputs toolchain-bin ];
    };
  };
}
