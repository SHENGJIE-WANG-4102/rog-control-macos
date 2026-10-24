# ROG Control for macOS

[简体中文](README.zh-CN.md) · English · **v0.3** · [Changelog](CHANGELOG.md)

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
| Custom CPU power limits / fan curves | Requires bridge 1.5.0 with quiet-preset floor validation; earlier 1.4.0 fan response, targets up to 175/175 W and factory restoration tested on G815LW. New quiet-preset hardware validation and sustained power-ceiling verification remain pending |
| Brightness, keyboard lighting | Not implemented |

The app does not invent sensor values. Missing data is displayed as unavailable. CPU power is a sensor-derived estimate for the CPU package, not whole-laptop wall power. Average CPU frequency is not the peak clock of the fastest core.

Factory profiles can influence firmware behaviour, but the application does not claim that custom PL1/PL2 or GPU TGP control has been validated.

### Custom tuning (v0.3)

**Monitor** and **Tuning** are tabs within one window. Switching tabs preserves the draft while one-second monitoring continues. The **Tuning** page edits eight-point curves for the CPU, GPU, and third fan together with CPU PL1/PL2 targets. It requires bridge **1.5.0**, AC power, the audited firmware fingerprint, and an explicit factory-curve read before applying. CPU limits satisfy **5 ≤ PL1 ≤ PL2 ≤ 175 W**, enforced by the GUI, helper, and kernel. Temperatures strictly increase within 20–100°C. Demand stays within 0–100%, never decreases with temperature, and the complete curve must remain above the temperature-interpolated quiet preset. The final point is not locked to 100%. Factory tables are displayed without silently changing their values; an incompatible table must be edited before application.

Drag points directly on the graph or edit the table. Axes span 20–100°C and 0–100% with 10-unit grid lines; edits snap to 1°C/1%. Temperatures remain at least 1°C apart. Raising a point lifts affected subsequent points; lowering one lowers affected previous points. The lower bound is the explicitly read quiet preset, linearly interpolated at the relevant temperature and drawn as a grey dashed line. The final point is adjustable above that floor. Validation covers intervals and endpoint extension, so points are raised as needed if a straight segment or tail would fall below the preset. The kernel enforces the same interpolation policy.

Dragging preserves the grab offset. Empty clicks and point clicks without movement are no-ops; leaving the plot stays bounded and disabling editing cancels the gesture. Completing a table edit applies the same cascade and floor rules. Graph and keyboard edits change only the draft; all three curves and power targets must pass validation before explicit application.

**Save preset** (`保存方案…`) writes the draft curves and PL1/PL2 to JSON. After reading factory curves, use **Load preset** (`载入方案…`) to fill the editor, then explicitly apply the settings. Documents include a format version and G815LW model identifier; unknown formats, other models, extra fields, and invalid values are rejected. Saving, loading, and previewing never send hardware requests or enable automatic application at login. The window scrolls on smaller screens, and one-second monitoring preserves the current draft and editing focus.

On this firmware, writing curves enters manual mode (`FANM=4`), which is required for the CPU power endpoints. All three curves and both power targets form one explicit transaction. A failed partial application attempts to restore the original factory profile and records whether recovery was confirmed. **A hung synchronous firmware call cannot be interrupted by this recovery.** Startup, shutdown, and automatic sensor refresh do not read factory curves or write tuning settings. There is no automatic reapplication at login.

Power confirmation reads the firmware target bytes `M6F0`/`M6F1`; this does not prove the CPU's sustained power under load. Curve writes confirm the firmware acknowledgment and manual mode, not a readback of the applied custom curve. Factory-curve queries return preset tables. On G815LW, all three factory tables, custom fan response, 80/100 W and 175/175 W target readbacks, and restoration to Turbo were tested. A roughly 12-second, 24-thread CPU test with all three fan curves at 100% recorded a maximum package-temperature reading of 75°C and fan readings around 6600/6300/7500 RPM. This is a short functional test, not long-term stability validation.

Fast SMC package-power polling produced alternating zero and spiking readings in this test. Those raw readings do not establish the true instantaneous power or prove the sustained hardware ceiling. PL1/PL2 targets are not an absolute instantaneous package-power cap: Intel describes PL1 as an average-power threshold and PL2 as a threshold that triggers rapid limiting after an overshoot; see [Intel package power control](https://edc.intel.com/content/www/us/en/design/products/platforms/details/arrow-lake-s/core-ultra-200s-series-processors-datasheet-volume-1-of-2/005/package-power-control/). This implementation does not read or change optional PL3/PL4 settings. Long-term stability, independent package-power verification, other models/firmware, and GPU TGP tuning remain unverified.

Bridge 1.5.0 adds quiet-curve queries only to the explicit read operation, without switching the factory profile. Startup and sensor refresh do not issue these queries. Existing 1.4.0 hardware trials do not validate the new quiet-floor policy.

Use **Restore factory policy** to return to the captured factory profile. Selecting a factory profile in the main window also exits custom mode. If the firmware retains manual mode across a reboot and no baseline is known, select a factory profile first, then explicitly read its curves. Changing this kernel bridge requires a restart; building the project alone does not install it or change boot configuration.

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

Factory profiles and monitoring support an already loaded `ROGFirmwareProbe` **1.3.0, 1.4.0 or 1.5.0** bridge; custom tuning requires **1.5.0**. Building or opening the app does **not** install a kernel extension, rebuild a kernel cache, patch EFI, or change boot arguments.

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

Firmware calls are synchronous. A user-space timeout cannot cancel a stuck ACPI/SMI call. The driver evaluates no firmware objects during `start`, `stop`, or `free`; write operations require explicit requests to fixed factory-profile, three-fan-curve, and PL1/PL2 endpoints, with no arbitrary ACPI, EC, or MSR access. Fan response and power-target readbacks have passed short functional trials; sustained hardware power enforcement and long-term stability remain unverified.

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
