with (import <nixpkgs> {});

mkShell {
  nativeBuildInputs = [
    linuxPackages.kernel
    gdb
    parted
    ccache
  ];
  inputsFrom = [
    linuxPackages.kernel
    qemu_kvm
  ];
  hardeningDisable = [ "fortify" ];
}
