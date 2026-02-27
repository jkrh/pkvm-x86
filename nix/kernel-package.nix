{
  pkgs,
  isGuest,
  ...
}:
let
  # Portable default: pinned upstream linux tree.
  defaultKernelSrc = builtins.fetchGit {
    url = "https://github.com/tiiuae/pKVM-x86.git";
    ref = "linux-6.12.y-pkvm-dev";
    rev = "50b5d7c5decca0ff4d935fe6f59c326d351ebfda";
  };
  defaultKernelVersion = "6.12.58";

  # For building local kernel, e.g.:
  # LINUX_SRC=$PWD/linux nix build .#linux-pkvm-host --impure --no-write-lock-file
  localKernelSrc = builtins.getEnv "LINUX_SRC";
  withLocalKernel = localKernelSrc != "";

  kernelSrc =
    if withLocalKernel then
      builtins.fetchGit {
        # Local override from git working tree:
        # includes tracked uncommitted changes; excludes .git and ignored/untracked files.
        url = "file://${localKernelSrc}";
      }
    else
      defaultKernelSrc;

  # Override version:
  # LINUX_KERNEL_VERSIO=6.18.0 nix build <target> --impure --no-write-lock-file
  kernelVersionOverride = builtins.getEnv "LINUX_KERNEL_VERSION";

  kernelVersion =
    if kernelVersionOverride != "" then
      kernelVersionOverride
    else if withLocalKernel then
      kernelVersionFromSource localKernelSrc
    else
      defaultKernelVersion;

  kernelVersionFromSource = import ./kernel-version.nix { lib = pkgs.lib; };

in
pkgs.callPackage ./linux-pkvm-x86.nix {
  inherit
    pkgs
    kernelSrc
    kernelVersion
    isGuest
    ;
  argsOverride = pkgs.lib.optionalAttrs withLocalKernel {
    preConfigure = ''
      make ARCH=x86_64 mrproper
    '';
  };
}
