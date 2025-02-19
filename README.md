This is a pKVM-IA fork that makes the PKVM work with the full feature set
provided by the KVM. This includes working with non-modified system BIOSs,
Operating Systems and hardware flavors that do not support Virtualized
Exceptions (#VEs), including the KVM VCPU itself.

In addition, the goal is to provide guests usable secure SMM state like
the stock KVM does, just one that is protected by the EPT also from the
host attack attempts. The use case we are after is not direct device
emulation but rather providing the guest a protected state out of the
host reach. This state can chain up to the real trust source accessible
via the sample API implemented against coreboot.

Beyond the basic functionality, the PKVM is extended with tools for guest
debugging and validation for any given set of virtual devices.
