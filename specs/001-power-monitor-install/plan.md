# Implementation Plan: Power Monitor Installation

**Branch**: `001-power-monitor-install` | **Date**: 2026-01-27 | **Spec**: [spec.md](./spec.md)
**Input**: Feature specification from `/specs/001-power-monitor-install/spec.md`

## Summary

This feature enhances the vision-sensor installation script (scripts/install.sh) to install and configure WittyPi 4 Mini power management hardware and INA219 power monitoring capabilities, modeled after the proven edge-sensor implementation. The installation provides autonomous power scheduling (7 AM - 9:30 PM daily operation), RTC-based timekeeping for offline accuracy, automatic boot-on-power-restore, and continuous power consumption monitoring with 30-day retention. All components are designed for graceful degradation - the system continues operating with reduced functionality if optional hardware (WittyPi, INA219) is unavailable, maintaining field deployment reliability.

**Technical Approach**: Extend existing bash-based installation script with new functions for WittyPi installation, systemd service creation for RTC synchronization and power monitoring, and robust error handling that logs warnings for optional component failures while continuing installation. Reference implementation from ../edge-sensor/scripts/install.sh provides battle-tested patterns for I2C enablement, first-boot configuration, and power schedule processing.

## Technical Context

**Language/Version**: Bash 4.0+ (Raspberry Pi OS default shell)
**Primary Dependencies**:
- WittyPi 4 software (downloaded from uugear.com during installation)
- System packages: i2c-tools, python3-smbus (for I2C communication)
- systemd (service management, timers)
- timedatectl (NTP and timezone management)

**Storage**: File-based logging to /var/log/power_daily (30-day retention, ~2MB total)
**Testing**: Manual integration testing on Raspberry Pi hardware with WittyPi 4 Mini and INA219 connected
**Target Platform**: Raspberry Pi OS (Debian-based, systemd-enabled)
**Project Type**: Embedded system installation script (single project, bash scripting)
**Performance Goals**:
- Installation completes within 5 minutes with network connectivity
- Power monitoring sampling: 60-second intervals
- Service restart: <15 seconds after failure
- RTC sync: <35 seconds when NTP available

**Constraints**:
- Installation must work with degraded functionality when WittyPi hardware not connected
- No rollback on optional component failures (continue with warnings)
- Must preserve existing install.sh structure and error handling patterns
- Requires root privileges (sudo execution)
- Network connectivity required for WittyPi software download (graceful failure if unavailable)

**Scale/Scope**:
- Single installation script (~600-800 additional lines based on edge-sensor reference)
- 4 new systemd service files (wittypi-firstboot, wittypi-rtc-sync, wittypi-rtc-sync timer, power-monitor)
- 1 new monitoring script (witty_pi_monitor.sh to be copied from reference implementation)
- 1 schedule file (daily_7am_to_930pm.wpi)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Principle I: Edge-First Design
✅ **PASS** - Power monitoring and RTC timekeeping operate autonomously without network dependency. NTP sync is opportunistic (30s timeout then proceeds). WittyPi schedule operates based on local RTC, not cloud time services. Network unavailability during installation logs warnings and continues.

### Principle II: Resource Constraint Discipline
✅ **PASS** - Installation script adds minimal runtime overhead:
- Power monitoring: ~5MB memory for Python script sampling every 60 seconds
- Log storage: ~2MB for 30 days of power data
- WittyPi software: ~10MB disk space
- All well within Pi Zero 2W constraints (512MB RAM, 8GB storage minimum)
- No continuous CPU load (monitoring script sleeps 60s between samples)

### Principle III: Reliability & Graceful Degradation
✅ **PASS** - Installation continues with degraded functionality when:
- WittyPi hardware not connected (logs warning, skips configuration)
- I2C initialization fails (logs error, continues with other components)
- python3-smbus installation fails (logs warning, continues without power monitoring)
- Schedule file missing (logs warning, allows manual configuration later)
- Power monitor service restart policy: automatic with 10-second delay
- No blocking failures for optional components

### Principle IV: Security-by-Default
✅ **PASS** - Installation maintains existing security posture:
- No new network-facing services (power monitoring is local only)
- No new authentication mechanisms required
- Service files run as root (required for I2C hardware access)
- Log directory (/var/log/power_daily) has standard permissions (755)
- WittyPi software downloaded over HTTPS from vendor (uugear.com)

### Principle V: Observable Operations
✅ **PASS** - Enhanced observability:
- Installation logs all actions (info/warn/error levels) to console and /tmp/vision_sensor_install.log
- Power monitoring creates structured time-series data (timestamp, voltage, current, power)
- Installation summary displays WittyPi status, RTC sync status, power monitor service status
- Systemd journal captures all service startup/failure events
- Each optional component failure generates actionable warning message

**Gate Result**: ✅ ALL GATES PASSED - Proceed to Phase 0 research

## Project Structure

### Documentation (this feature)

```text
specs/001-power-monitor-install/
├── plan.md              # This file
├── research.md          # Phase 0: Technology decisions and patterns
├── data-model.md        # Phase 1: Power monitoring data structure
├── quickstart.md        # Phase 1: Testing and validation guide
├── contracts/           # Phase 1: Systemd service contracts
│   ├── power-monitor.service
│   ├── wittypi-firstboot.service
│   ├── wittypi-rtc-sync.service
│   └── wittypi-rtc-sync.timer
└── tasks.md             # Phase 2: Implementation task breakdown (NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
scripts/
└── install.sh           # MODIFIED: Add power monitor installation functions

scripts/templates/       # NEW: Service and configuration templates
├── power-monitor.service
├── wittypi-firstboot.service
├── wittypi-rtc-sync.service
├── wittypi-rtc-sync.timer
├── daily_7am_to_930pm.wpi
└── witty_pi_monitor.sh  # NEW: Power monitoring script (copied from edge-sensor)

tests/                   # NEW: Integration test directory
└── test_power_monitor_install.sh  # Manual validation script for hardware testing
```

**Structure Decision**: Single project structure using existing scripts/ directory. Installation script is self-contained bash with no build process. New systemd service templates and monitoring script stored in scripts/templates/ directory alongside install.sh, following the pattern established by existing service templates (vision-sensor.service). Test directory added for hardware validation scripts.

## Complexity Tracking

No constitution violations requiring justification. All principles passed cleanly.
