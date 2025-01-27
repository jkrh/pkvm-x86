This is a pKVM-IA fork that makes the PKVM work with the full feature set
provided by the KVM. This includes working with non-modified system BIOSs,
Operating Systems and hardware flavors that do not support Virtualized
Exceptions (#VEs), including the KVM VCPU itself.

In addition, the goal is to provide each guest with an SMM mode visible
only to the hypervisor, in other words, unreachable for both the guest
and the host. When chained correctly with the system SMM building up to a
real trust source, the guests can have access to a VM specific secure key
storage & crypto units without being dependent on 'untrusted' entities
that cannot be validated & extended like the TPM.

Beyond the basic functionality, the PKVM is extended with tools for trusted
guest debugging and validation for any given set of virtual devices.
