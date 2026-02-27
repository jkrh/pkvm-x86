{
  lib,
  pkgs,
  buildLinux,
  kernelSrc,
  kernelVersion,
  isGuest ? false,
  structuredExtraConfig ? { },
  patches ? [ ],
  ...
}@args:
let
  variant = if isGuest then "guest" else "host";
  variants = with pkgs.lib.kernel; {
    guest = {
      HYPERVISOR_GUEST = yes;
      PKVM_GUEST = yes;
    };
    host = {
      KVM = yes;
      KVM_INTEL = yes;
      PKVM_INTEL = yes;
      PKVM_INTEL_VE_MMIO = yes;
      PKVM_INTEL_VE_EMULATION = yes;
      PKVM_INTEL_DEBUG = yes;
      PKVM_INTEL_FORCE_PROTECTED_VM = yes;
      PKVM_INTEL_PROTECTED_VM_COREDUMP = yes;
      KSM = pkgs.lib.mkForce no;
      IOMMU_DEFAULT_PASSTHROUGH = yes;
      INTEL_IOMMU = yes;
    };
  };
  version = "${kernelVersion}-pkvm-${variant}";

  pkvmKernel = buildLinux (
    {
      inherit version patches;
      modDirVersion = kernelVersion;

      src = kernelSrc;
      structuredExtraConfig = pkgs.lib.recursiveUpdate variants.${variant} structuredExtraConfig;

      extraMeta = {
        platforms = with lib.platforms; lib.intersectLists x86 linux;
      };
    }
    // args.argsOverride or { }
  );
in
pkvmKernel
