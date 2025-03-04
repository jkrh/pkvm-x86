{pkgs ? import <nixpkgs> {}}:
with pkgs;
mkShellNoCC {
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
  hardeningDisable = [ "fortify" ];
}
