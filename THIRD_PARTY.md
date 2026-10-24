# Dependencies and implementation references

The MIT license in this repository covers its original application, helper, and firmware-bridge code. It does not relicense external software.

- **macOS SDK / Apple frameworks:** AppKit, Foundation, IOKit, Security and system tools are supplied by Apple. They are used under their applicable SDK and system licenses and are not redistributed here.
- **MacKernelSDK:** an optional, separately obtained build dependency for `Driver/`. Consult the [upstream repository](https://github.com/acidanthera/MacKernelSDK) and notices for the individual headers/libraries. SDK sources and archives are not vendored.
- **VirtualSMC / SMCProcessor:** a separately installed sensor provider. [Upstream source](https://github.com/acidanthera/VirtualSMC) was consulted to identify temperature and package-energy SMC keys. Its sources and binaries are not included. In particular, `PCPC` is mapped to core-domain power in SMCProcessor; this project uses `PCPR` for the package-energy domain.
- **G-Helper:** the [ASUS ACPI interface](https://github.com/seerge/g-helper/blob/main/app/AsusACPI.cs) was consulted for factory profile endpoint `0x00120075` and its mode values. The native macOS implementation is independently written; G-Helper sources and binaries are not included.
- **Linux asus-wmi:** [upstream driver](https://github.com/torvalds/linux/blob/master/drivers/platform/x86/asus-wmi.c) and interface definitions were consulted for ASUS WMI protocol semantics. Linux source is not bundled.
- **NullMoth NVIDIA driver / 1401:** an optional, independently installed graphics stack on the development machine. No NVIDIA or NullMoth binaries, source, firmware, or patches are included in this project. GPU telemetry from this stack is not currently implemented.

Protocol identifiers and references do not grant rights to redistribute another project's implementation. Contributions that import or adapt external code must retain its notices and be checked for license compatibility before inclusion.
