{
  pkgs,
  isGuest,
  ...
}:
let
  # Portable default: pinned upstream linux tree.
  defaultKernelSrc = fetchGit {
    url = "https://github.com/tiiuae/pKVM-x86.git";
    ref = "linux-6.12.y-pkvm-dev";
    rev = "aa0146f8ccf787a78d4aefb13367be7cff99ac90";
  };
  # For building local kernel, e.g.:
  # LINUX_SRC=$PWD/linux nix build .#linux-pkvm-host --impure --no-write-lock-file
  localKernelSrc = builtins.getEnv "LINUX_SRC";
  withLocalKernel = localKernelSrc != "";

  kernelSrc =
    if withLocalKernel then
      fetchGit {
        # Local override from git working tree:
        # includes tracked uncommitted changes; excludes .git and ignored/untracked files.
        url = "file://${localKernelSrc}";
      }
    else
      defaultKernelSrc;

  # Override version:
  # LINUX_KERNEL_VERSION=6.18.0 nix build <target> --impure --no-write-lock-file
  kernelVersionOverride = builtins.getEnv "LINUX_KERNEL_VERSION";

  kernelVersion =
    if kernelVersionOverride != "" then
      kernelVersionOverride
    else
      kernelVersionFromSource kernelSrc;

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
