This is a pKVM-IA fork that makes the PKVM work with the full feature set
provided by the KVM. This includes working with non-modified system BIOSs,
Operating Systems and hardware flavors that do not support Virtualized
Exceptions (#VEs), including the KVM VCPU itself.

In addition, the goal is to provide multiple secure smm states via the
hypervisors help. The pkvm acts as a barrier to secure the system smm and
provides the guests a properly isolated smm state that the host cannot
access.

Beyond the basic functionality, the PKVM is extended with tools for guest
debugging and validation for any given set of virtual devices.
