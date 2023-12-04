with (import <nixpkgs> {});

mkShell {
  nativeBuildInputs = [
    linuxPackages.kernel
    gdb
    parted
  ];
  inputsFrom = [
    linuxPackages.kernel
    qemu_kvm
  ];
}
