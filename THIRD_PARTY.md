# Dependencies and implementation references

The MIT license in this repository covers its original application, helper, and firmware-bridge code. It does not relicense external software.

- **macOS SDK / Apple frameworks:** AppKit, Foundation, IOKit, Security and system tools are supplied by Apple. They are used under their applicable SDK and system licenses and are not redistributed here.
- **MacKernelSDK:** an optional, separately obtained build dependency for `Driver/`. Consult the [upstream repository](https://github.com/acidanthera/MacKernelSDK) and notices for the individual headers/libraries. SDK sources and archives are not vendored.
- **VirtualSMC / SMCProcessor:** a separately installed sensor provider. [Upstream source](https://github.com/acidanthera/VirtualSMC) was consulted to identify temperature and package-energy SMC keys. Its sources and binaries are not included. In particular, `PCPC` is mapped to core-domain power in SMCProcessor; this project uses `PCPR` for the package-energy domain.
- **G-Helper:** the [ASUS ACPI interface](https://github.com/seerge/g-helper/blob/main/app/AsusACPI.cs) was consulted for factory profile endpoint `0x00120075` and its mode values. The native macOS implementation is independently written; G-Helper sources and binaries are not included.
- **Linux asus-wmi:** [upstream driver](https://github.com/torvalds/linux/blob/master/drivers/platform/x86/asus-wmi.c) and interface definitions were consulted for ASUS WMI protocol semantics. Linux source is not bundled.
- **NullMoth NVIDIA driver / 1401:** an optional, independently installed graphics stack on the development machine. No graphics-driver implementation, binaries, firmware, or patches are bundled. Its existing user-client interface is accessed by independently written IOKit code for read-only telemetry.
- **NVIDIA open-gpu-kernel-modules:** `Sources/RMRUSD.h` contains an adapted MIT-licensed ABI subset. Definitions and offsets were checked against [610.57.04 cl00de.h](https://github.com/NVIDIA/open-gpu-kernel-modules/blob/610.57.04/src/common/sdk/nvidia/inc/class/cl00de.h), `nvos.h`, `cl0080.h`, and public control headers. The NVIDIA copyright and license notice is retained in that file and below. Kernel implementation and firmware are not included.
- **nvidia-gpu-sensors:** [Philip Langdale's MIT-licensed project](https://github.com/philipl/nvidia-gpu-sensors) was consulted as a reference for the RM shared-data workflow. Its Linux executable and raw-register sensor code are not included or used.

Protocol identifiers and references do not grant rights to redistribute another project's implementation. Contributions that import or adapt external code must retain its notices and be checked for license compatibility before inclusion.

## NVIDIA ABI notice (MIT)

Copyright (c) 2022-2026 NVIDIA CORPORATION & AFFILIATES. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
