# Changelog

[简体中文](CHANGELOG.zh-CN.md) · [README](README.md)

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
