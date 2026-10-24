# Changelog

[简体中文](CHANGELOG.zh-CN.md) · [README](README.md)

## v0.2 — 2026-10-25

### Added

- Read-only NVIDIA RM monitoring for GPU temperature, actual graphics clock, and instantaneous GPU power.
- A VRAM and load panel showing allocated VRAM / allocatable pool, memory temperature, actual memory clock, and GPU utilization, with one-second incremental updates.
- Average GPU power, memory-controller busy percentage, P-state, and raw sample timestamps in diagnostic JSON.
- Driver-version, shared-data sequence, bounds, unit, and range validation. Each snapshot releases its private RM client, objects, and read-only mapping; no graphics-driver, boot-argument, display, or power-policy changes are required.
- Mocked RM transport tests covering the query allowlist, unsupported versions, units, stale/invalid fields, mapping bounds, and cleanup on request failures.
- NVIDIA MIT ABI notices in the source, third-party documentation, and built application.

### Fixed

- Live GPU readings becoming unavailable when RM timestamps differ from the system wall clock. Freshness now requires observed timestamp advancement and uses a local monotonic clock to reject fields frozen for more than three seconds.
- Reconfirm sensor updates after a long idle period or a backwards RM timestamp. Invalid fields are rejected individually rather than filled with estimated values.

### Compatibility and validation

- Supports the ASUS ROG 枪神 9 series; **only G815LW has been tested on real hardware**. GPU monitoring was tested with RTX 5080 Laptop, NullMoth NVRM **2.4.3**, and NVIDIA **610.57.04** on macOS 26.
- Thirty continuous snapshots had no invalid readings after initialization. GUI readings, pending-profile selection during refresh, password-free relaunch, and idle helper behavior were verified. Internal 240 Hz and external 160 Hz remained available.
- Application builds, signature validation, static analysis, firmware contract tests, and RM transport/failure-path tests passed.

### Limitations

- Other RM versions remain disabled until their shared-data layout is checked. Initial readings may need the next polling cycle to confirm timestamp advancement.
- VRAM totals describe RM's allocatable pool after reserved memory; memory clock is not an effective GDDR data rate. GPU power is a measured reading, not a configured TGP limit.
- Custom power limits, manual fan curves, brightness, and keyboard lighting remain disabled.

## v0.1 — 2026-10-25

First public source release of ROG Control for macOS.

### Compatibility

- Supports the ASUS ROG 枪神 9 series; **only G815LW has been tested on real hardware**, running macOS 26.
- Other models and BIOS revisions remain unverified. The firmware bridge rejects unknown DSDT fingerprints; additional audited profiles may be required.

### Added

- Native AppKit control panel with Silent, Performance, and Turbo selection.
- Explicit AC-powered factory-profile changes, verified by firmware readback.
- CPU, GPU, and third-fan RPM monitoring.
- CPU temperature, CPU package power, and interval-average frequency using existing SMC providers and `powermetrics`.
- One-time privileged helper installation with automatic connection on later launches. Replacing a development build can require approving its new code identity.
- One-second automatic readings and manual refresh. Background reads keep profile selection available; user actions are queued ahead of later background reads.
- Updates limited to changed labels, colors, and control states, while preserving an unapplied profile selection.
- Model/firmware definitions in `Driver/Profiles.hpp`, separate application and driver build scripts, request validation, and host-simulated firmware command tests.
- English and Simplified Chinese documentation, MIT license, and third-party notices.

### Fixed during development

- Cards and controls overflowing the window width.
- Initial readings appearing live while the control component was disconnected.
- Background polling briefly disabling profile controls.
- Unnecessary repeated control updates and excessive status text.

### Validation

- Real-device Silent and Performance changes, fan-speed changes, and restoration to Turbo.
- GUI profile changes, pending-selection preservation during polling, and relaunch without another password.
- Idle helper verification with no firmware polling while the GUI is closed.
- Rejection of an unapproved same-user client without dispatching a firmware request.
- Application/driver builds, signing checks, static analysis, and hardware-free request/failure-path tests.

### Known limitations

- NVIDIA GPU frequency, power, and temperature monitoring is **not yet implemented for the current RM backend**. Missing readings are displayed as unavailable; this is not evidence that the hardware has no query interface.
- Custom CPU/GPU power limits, manual fan curves, brightness, and keyboard lighting are not enabled.
- The app does not automatically install the kernel bridge, change EFI, rebuild a system kernel cache, or modify boot arguments.
- Firmware calls are synchronous; user-space timeouts cannot cancel a blocked firmware call.
