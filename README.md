This is a PKVM-IA fork that attempts to make the PKVM work correctly
with full feature set provided by the KVM. This includes working
with non-modified system BIOSs and hardware flavors that do not
support #VE, including the KVM VCPU itself.

In addition the goal is to provide each guest SMM mode visible for
the hypervisor only, in other words unreachable for both the guest
and the host. When chained correctly with the system SMM, the guests
can have relatively secure custom key storage & crypto unit without
being dependent on the TPM functionality.

Beyond the basic functionality the PKVM is extended with tools for
the trusted guest debugging and validation for any given set of
virtual devices.
