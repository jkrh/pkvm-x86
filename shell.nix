{
  pkgs ? import <nixpkgs> { },
}:
with pkgs;
let
  buildInputsFrom =
    inputs: (lib.subtractLists inputs (lib.flatten (lib.catAttrs "buildInputs" inputs)));

in
mkShellNoCC rec {
  nativeBuildInputs = [
    linuxPackages.kernel
    gdb
    parted
    ccache
  ];
  inputsFrom = [
    linuxPackages.kernel
    qemu_kvm
    crosvm
    coreboot-toolchain.x64
  ];
  # shared libraries for running
  packages = buildInputsFrom inputsFrom;

  hardeningDisable = [ "fortify" ];
}
