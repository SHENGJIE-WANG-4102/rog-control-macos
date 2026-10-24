# ROG Control for macOS

[简体中文](README.zh-CN.md) · English · **v0.2** · [Changelog](CHANGELOG.md)

A native macOS control panel targeting the **ASUS ROG 枪神 9 series**: factory performance profiles, fan monitoring, and CPU/GPU sensor views.

**Supported series: ASUS ROG 枪神 9. Only G815LW has been tested on real hardware.** Other models and BIOS revisions have not been validated and may require an additional audited firmware profile before mode control works.

**Early experimental release.** Factory profile control has been tested on an ASUS ROG Strix G18 **G815LW** running macOS 26. The included firmware bridge deliberately accepts one audited DSDT fingerprint. It is not a generic driver for every ROG model. This is an independent project, not an ASUS product.

## What works

| Feature | Status |
| --- | --- |
| Silent / Performance / Turbo | Tested with firmware readback and real fan-speed changes |
| CPU, GPU, and third fan RPM | Tested; one-second refresh while the app is visible |
| CPU temperature | Reads the existing SMC temperature provider |
| CPU package power | Reads the SMC package-energy provider; not the core-only power key |
| CPU frequency | Attempts `powermetrics` interval-average frequency; unavailable if the platform does not report it |
| GPU frequency, power, temperature | Read-only NVIDIA RM shared telemetry; tested with NullMoth NVRM 2.4.3 / NVIDIA 610.57.04 on RTX 5080 Laptop |
| Allocated VRAM, memory temperature/clock, GPU utilization | Tested through the same RM backend; one-second GUI refresh |
| Authorization | One-time privileged helper installation; subsequent launches connect without a password |
| Custom power limits / fan curves | Not enabled |
| Brightness, keyboard lighting | Not implemented |

The app does not invent sensor values. Missing data is displayed as unavailable. CPU power is a sensor-derived estimate for the CPU package, not whole-laptop wall power. Average CPU frequency is not the peak clock of the fastest core.

Factory profiles can influence firmware behaviour, but the application does not claim that custom PL1/PL2 or GPU TGP control has been validated.

### NVIDIA telemetry (v0.2)

The RM reader opens its own client, reads a read-only `RM_USER_SHARED_DATA` mapping, and frees its objects and mapping after each snapshot. It does not initialize/reset the GPU, read raw registers, change clocks/power limits, or modify the installed graphics driver. It also works without administrator privileges. The control service still requires authorization for firmware profile changes and CPU sampling.

RUSD has no negotiated layout version. The backend currently accepts only the tested NVRM **2.4.3** pairing; other versions remain unavailable until their ABI is checked. Invalid, inconsistent, out-of-range, or stale polled fields are rejected individually. Freshness requires observed RM timestamp advancement and expires after three seconds without an update, measured with a local monotonic clock. RM timestamps are not compared directly to the system wall clock. Startup/after idle can need up to half a second to confirm an update. PMA allocation statistics use NVIDIA's sequence counter instead.

The main GPU power value is **instantaneous GPU power**, not a configured TGP limit. The diagnostic JSON also includes average GPU power, memory-controller busy percentage, and P-state. **Allocated VRAM / total** describes RM's allocatable PMA pool, excluding reserved VRAM; it is not the physical memory capacity printed on the GPU specification. Memory-controller busy percentage is not VRAM allocation. The memory clock is the reported actual clock, not an effective GDDR data rate.

Read the sensors without a firmware request or administrator privileges:

```sh
"dist/ROG Control for macOS.app/Contents/MacOS/ROGControl" --read-sensors
```

## Build and run

Requires an Intel macOS environment with Xcode Command Line Tools. The app uses AppKit, Foundation, IOKit, and Security; there are no package-manager dependencies.

```sh
xcode-select --install
./script/build_and_run.sh
```

The generated application is `dist/ROG Control for macOS.app`. To build without opening a window:

```sh
./script/build_and_run.sh --build-only
```

`--verify`, `--debug`, `--logs`, and `--telemetry` are also supported.

The current app expects the compatible `ROGFirmwareProbe` **1.3.0** bridge already installed. Building or opening the app does **not** install a kernel extension, rebuild a kernel cache, patch EFI, or change boot arguments.

### Firmware bridge

`Driver/` contains the bridge source and metadata. Building it requires the external [MacKernelSDK](https://github.com/acidanthera/MacKernelSDK):

```sh
git clone https://github.com/acidanthera/MacKernelSDK.git Vendor/MacKernelSDK
./Driver/build.sh
```

Alternatively set `MAC_KERNEL_SDK` to an existing SDK checkout. Building produces a local kext only. Installation is intentionally not automated: kernel-extension deployment and recovery depend on the host's boot configuration. Do not remove the firmware fingerprint guard to try an unaudited model.

Audited model/BIOS entries live in `Driver/Profiles.hpp`. A family name is not a compatibility check. Add an entry only after auditing that machine’s firmware and validating the endpoint behaviour.

The retained `ROGFirmwareProbe` name is the interface used by the already tested bridge.

## Use

1. Open the app with the matching bridge loaded.
2. Click **Authorize once** (currently shown as `授权一次…`) and complete the native macOS administrator dialog. This installs a small control service.
3. Choose Silent, Performance, or Turbo, then click Apply. Mode changes require AC power and are verified by reading the firmware state back.
4. Enable or disable automatic readings. Closing the app stops GUI polling; the chosen factory profile stays selected.

The service starts at boot and waits for requests. Its idle startup path does not query firmware, sample sensors, or change profiles. It accepts a narrow command set from the approved signed GUI running as the configured user. Client code-signature validation, local socket permissions, firmware matching, and mode range checks are separate boundaries. Rebuilding the GUI changes its code identity and can require another installation authorization.

The local development build is ad-hoc signed, not notarized. The current interface is Chinese; both project readmes are maintained.

### Remove the control service

```sh
sudo /Library/PrivilegedHelperTools/com.macdriver.ROGControlHelper --uninstall
```

This removes the user-space control service. It leaves the separately installed firmware bridge and current factory profile unchanged. Remove the app bundle separately if desired.

## Verification

```sh
./script/test.sh
```

These tests check request validation, the actual firmware-command methods against a host simulator, and the RM reader with mocked transport, stale/invalid fields, units, version rejection, and cleanup failures. They do not prove BIOS responsiveness or hardware compatibility. On-device testing verified Silent and Performance mode changes, all three fan readings, restoration to the original Turbo profile, and live RM telemetry on the tested GPU/driver pairing.

Firmware calls are synchronous. A user-space timeout cannot cancel a stuck ACPI/SMI call. The driver evaluates no firmware objects during `start`, `stop`, or `free`; write operations are explicit, restricted to the factory-profile endpoint, and do not expose arbitrary ACPI, EC, or MSR access. Custom fan-curve/power paths remain disabled pending further validation.

## Layout

- `Sources/`: native application, privileged helper, sensor readers, and bridge client.
- `Driver/`: model-restricted firmware bridge.
- `Tools/`: a command-line bridge client.
- `Tests/`: hardware-free command and failure-path tests.
- `script/`: reproducible build/run/test entrypoints.

No personal diagnostic logs, system backups, GPU drivers, firmware dumps, or EFI configurations are included.

## License and references

Original project code is licensed under [MIT](LICENSE). Dependencies and separately installed drivers keep their own licenses; they are not relicensed or bundled here. See [THIRD_PARTY.md](THIRD_PARTY.md).

[Source repository](https://github.com/SHENGJIE-WANG-4102/rog-control-macos)
