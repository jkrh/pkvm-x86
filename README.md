This is a pKVM-IA fork that makes the PKVM work with the full feature set
provided by the KVM. This includes working with non-modified system BIOSs,
Operating Systems and hardware flavors that do not support Virtualized
Exceptions (#VEs), including the KVM VCPU itself.

In addition, the goal is to provide guests a secure SMM state. The guest
SMRAM lock request is terminated by the hypervisor and locked in the same
fashion as the host one. This state was put in the CPU for a good reason,
so let's put it in use rather than take it away. The recommended use case
for the guest SMM is to chain up to the real trust source accessible via
the sample API implemented against coreboot. The api can, among other
things, hook into a custom trust source in order to provide crypto and key
services for the guest.

Beyond the basic functionality, the PKVM is extended with tools for trusted
guest debugging and validation for any given set of virtual devices.
