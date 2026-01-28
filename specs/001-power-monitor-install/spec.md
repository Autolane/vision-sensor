# Feature Specification: Power Monitor Installation

**Feature Branch**: `001-power-monitor-install`
**Created**: 2026-01-27
**Status**: Draft
**Input**: User description: "Update the install script to similar to the install script at ../edge-sensor/scripts/install.sh we install and configure the power monitor service with the wittypi and the ina219. we should also be installing an setting the similar settings for the wittypi as in the install script. (on by default and the schedule)"

## Clarifications

### Session 2026-01-27

- Q: Power monitoring sampling interval - what frequency should power data be logged? → A: Every 60 seconds (1 minute intervals)
- Q: Power monitor service failure handling - what should happen if the service crashes or fails? → A: Restart automatically with 10-second delay
- Q: Power schedule timezone interpretation - are 7:00 AM and 9:30 PM in local time or UTC? → A: Local system timezone (configured during installation)
- Q: Power log data retention policy - how long should power monitoring logs be kept? → A: Keep 30 days of logs, delete older files
- Q: Installation failure rollback strategy - should installation rollback changes if a critical step fails? → A: Continue with degraded functionality, log warnings for failed components

## User Scenarios & Testing *(mandatory)*

### User Story 1 - WittyPi Installation and Auto-Boot Configuration (Priority: P1)

Field technicians installing vision sensor devices need the WittyPi 4 Mini hardware to be automatically detected, installed, and configured during the deployment installation process so that devices can reliably power on without manual intervention.

**Why this priority**: This is the foundational capability for power management. Without auto-boot configured, devices won't power on reliably after power loss, making all other power management features useless.

**Independent Test**: Can be fully tested by running the install script on a Raspberry Pi with WittyPi 4 Mini connected, then power cycling the device to verify it boots automatically.

**Acceptance Scenarios**:

1. **Given** a Raspberry Pi with WittyPi 4 Mini connected and the install script available, **When** the installation script is executed, **Then** WittyPi software is downloaded from uugear.com, installed to /opt/wittypi, and I2C is enabled
2. **Given** WittyPi software is installed, **When** the system boots for the first time after installation, **Then** a first-boot service performs initial system time to RTC sync (waiting up to 30 seconds for NTP) and enables auto-boot mode
3. **Given** auto-boot is enabled and the device is powered off, **When** power is restored to the device, **Then** the device automatically boots without button press
4. **Given** the first-boot configuration is complete, **When** the first-boot service completes successfully, **Then** the service removes itself from systemd to prevent re-execution

---

### User Story 2 - RTC Time Synchronization (Priority: P2)

System administrators need the device's real-time clock (RTC) to maintain accurate time across power cycles through ongoing synchronization services (shutdown sync and daily sync) so that power monitoring logs and system timestamps remain accurate even when network time is unavailable. Note: Initial first-boot RTC sync is handled by User Story 1.

**Why this priority**: Accurate time is critical for power monitoring data integrity and troubleshooting, but the system can still function (with degraded logging quality) if RTC sync fails.

**Independent Test**: Can be tested by setting system time via NTP, syncing to RTC, disconnecting from network, power cycling the device, and verifying system time is restored from RTC.

**Acceptance Scenarios**:

1. **Given** the device has network connectivity and NTP is enabled, **When** the first boot occurs after installation, **Then** system waits up to 30 seconds for NTP synchronization before syncing system time to RTC
2. **Given** RTC is synced with accurate time, **When** the system shuts down or reboots, **Then** a systemd service syncs current system time to the RTC before shutdown
3. **Given** the device boots without network connectivity, **When** WittyPi daemon starts, **Then** system time is synchronized from RTC to maintain accurate time
4. **Given** the device is running normally, **When** 24 hours have elapsed, **Then** a systemd timer triggers daily sync of system time to RTC

---

### User Story 3 - Power Schedule Configuration (Priority: P3)

Fleet operators deploying multiple vision sensors need devices to automatically power on at 7:00 AM local time and power off at 9:30 PM local time daily to conserve battery power during non-operating hours while ensuring sensors are active during peak monitoring periods.

**Why this priority**: This optimizes power usage and extends battery life, but devices can operate 24/7 if this feature is not configured. It's an enhancement rather than core functionality.

**Independent Test**: Can be tested by installing the power schedule, verifying schedule.wpi is processed correctly, and monitoring device power state at scheduled times.

**Acceptance Scenarios**:

1. **Given** a file named daily_7am_to_930pm.wpi exists in the installation directory, **When** the install script runs, **Then** the schedule file is copied to /opt/wittypi/wittypi/schedules/ and activated as schedule.wpi
2. **Given** the schedule file is installed, **When** the WittyPi runScript.sh processes the schedule, **Then** startup and shutdown times are configured for 7:00 AM and 9:30 PM in the local system timezone
3. **Given** the power schedule is active and the current time is 9:30 PM, **When** the scheduled shutdown time arrives, **Then** the device powers off automatically
4. **Given** the device is powered off and the current time reaches 7:00 AM, **When** the scheduled startup time arrives, **Then** the device powers on automatically

---

### User Story 4 - Power Monitor Service Installation (Priority: P2)

System administrators need power consumption data (voltage, current, power draw) from the INA219 sensor to be continuously logged to persistent storage so that battery health, power usage patterns, and hardware issues can be monitored and analyzed.

**Why this priority**: Power monitoring provides valuable operational insights and enables predictive maintenance, but the device operates normally without it.

**Independent Test**: Can be tested by verifying the power-monitor service starts successfully, logs are written to /var/log/power_daily, and data contains valid voltage/current readings from the INA219.

**Acceptance Scenarios**:

1. **Given** the installation script is running, **When** power monitor installation begins, **Then** python3-smbus and i2c-tools packages are installed for INA219 communication
2. **Given** dependencies are installed and witty_pi_monitor.sh exists, **When** the script is copied to /opt/power-monitor/, **Then** the monitoring script has executable permissions and is owned by root
3. **Given** the monitoring script is installed and power-monitor.service exists, **When** the systemd service is installed and enabled, **Then** the service starts automatically on boot
4. **Given** the power monitor service is running, **When** the service executes the monitoring script, **Then** power data is logged to /var/log/power_daily with timestamped voltage, current, and power readings

---

### Edge Cases

- What happens when WittyPi hardware is not connected during installation? (Installation continues with degraded functionality, logs warning, and skips WittyPi configuration)
- How does the system handle RTC sync timeout if NTP never becomes available? (Proceeds with current system time, logs warning, and continues installation)
- What happens if the daily_7am_to_930pm.wpi schedule file is missing? (Logs warning, skips schedule installation, continues with other components)
- How does the system behave if I2C is not enabled or fails to initialize? (Logs error, skips WittyPi configuration, continues with other components)
- What happens if python3-smbus installation fails? (Logs warning that battery voltage monitoring won't work, continues with other components)
- How does the system handle INA219 sensor not responding on I2C bus? (Power monitor service should log error and will restart automatically after 10 seconds)
- What happens if /opt/wittypi directory already exists from previous installation? (Should skip WittyPi download and use existing installation)
- What happens if power monitor service repeatedly fails? (Service continues restarting with 10-second delays indefinitely until issue is resolved)
- What happens if disk space is critically low and cannot accommodate 30 days of logs? (Log rotation continues but may retain fewer than 30 days depending on available space)

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Installation script MUST download WittyPi 4 software from uugear.com and install to /opt/wittypi system-wide location
- **FR-002**: Installation script MUST enable I2C interface on Raspberry Pi during WittyPi installation
- **FR-003**: Installation script MUST create a one-shot systemd service that configures WittyPi auto-boot on first reboot
- **FR-004**: First-boot service MUST wait up to 30 seconds for NTP synchronization before syncing system time to RTC
- **FR-005**: First-boot service MUST enable WittyPi auto-boot by writing 0x01 to I2C register I2C_CONF_DEFAULT_ON
- **FR-006**: First-boot service MUST verify auto-boot setting by reading back the register value
- **FR-007**: First-boot service MUST remove itself from systemd after successful configuration completion
- **FR-008**: Installation script MUST create a systemd service to sync system time to RTC before shutdown/reboot
- **FR-009**: Installation script MUST create a daily systemd timer to sync system time to RTC for long-term accuracy
- **FR-010**: Installation script MUST re-enable NTP service after WittyPi installation (WittyPi installation may disable it)
- **FR-011**: Installation script MUST install daily_7am_to_930pm.wpi power schedule if the file is available
- **FR-012**: Installation script MUST process the power schedule using runScript.sh to configure startup/shutdown times
- **FR-023**: Power schedule times (7:00 AM and 9:30 PM) MUST be interpreted in the local system timezone configured during installation
- **FR-013**: Installation script MUST install python3-smbus package for INA219 battery sensor communication
- **FR-014**: Installation script MUST install i2c-tools package for I2C diagnostics
- **FR-015**: Installation script MUST copy witty_pi_monitor.sh monitoring script to /opt/power-monitor/
- **FR-016**: Installation script MUST create /var/log/power_daily directory for power monitoring data storage
- **FR-017**: Installation script MUST install and enable power-monitor.service systemd service
- **FR-018**: Power monitor service MUST start automatically on system boot
- **FR-019**: Installation script MUST set REBOOT_REQUIRED flag when WittyPi or I2C configuration changes are made
- **FR-020**: Installation script MUST display reboot warning in installation summary when WittyPi is configured with message: "⚠️  REBOOT REQUIRED: WittyPi I2C configuration changes require system reboot to take effect. First-boot auto-boot configuration will run after reboot."
- **FR-021**: Power monitor service MUST sample and log voltage, current, and power readings every 60 seconds
- **FR-022**: Power monitor service MUST restart automatically after failure with a 10-second delay between restart attempts
- **FR-024**: Power monitoring system MUST automatically delete log files older than 30 days from /var/log/power_daily
- **FR-025**: Installation script MUST continue with degraded functionality when non-critical components fail (WittyPi, power monitor, schedule), logging warnings for each failure
- **FR-026**: Installation script MUST complete successfully and display summary even when optional components fail to install

### Key Entities *(include if feature involves data)*

- **WittyPi Configuration**: Represents the state of WittyPi hardware settings including auto-boot enabled/disabled, RTC time, and power schedule
- **Power Monitor Data**: Time-series data logged to /var/log/power_daily containing timestamp, voltage (V), current (mA), and power (W) readings from INA219, sampled every 60 seconds, with automatic retention of 30 days (older files deleted)
- **Systemd Services**: Collection of services managing RTC sync (wittypi-firstboot, wittypi-rtc-sync, wittypi-rtc-sync-daily) and power monitoring (power-monitor)
- **Power Schedule**: Configuration defining daily startup time (7:00 AM) and shutdown time (9:30 PM) in local system timezone, encoded in .wpi schedule file format

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Installation completes without errors when WittyPi 4 Mini hardware is connected to Raspberry Pi
- **SC-002**: Device automatically powers on within 5 seconds of power cable connection (power restoration) without manual button press
- **SC-003**: System time accuracy drifts less than 1 minute per week when disconnected from network time sources
- **SC-004**: Power monitor service logs voltage, current, and power readings every 60 seconds to persistent storage
- **SC-005**: Device powers on at 7:00 AM local time (±2 minutes) and powers off at 9:30 PM local time (±2 minutes) when schedule is configured
- **SC-006**: First-boot configuration service completes successfully and removes itself within 120 seconds of first boot
- **SC-007**: Installation script completes successfully with appropriate warnings when optional components (WittyPi, power monitor, schedule) fail to install
- **SC-008**: RTC time synchronization completes within 35 seconds when NTP is available (30s NTP wait + 5s sync)
- **SC-009**: Power monitor service automatically restarts within 15 seconds of failure (10-second delay + startup time)
- **SC-010**: Power log files older than 30 days are automatically deleted from /var/log/power_daily

## Assumptions *(optional)*

- WittyPi 4 Mini hardware is physically connected to Raspberry Pi GPIO during installation
- Raspberry Pi is running Raspberry Pi OS (Debian-based distribution with systemd)
- Installation script is executed with root privileges (sudo)
- Network connectivity is available during installation for downloading WittyPi software and packages
- The witty_pi_monitor.sh monitoring script file exists in scripts/templates/ directory
- The daily_7am_to_930pm.wpi schedule file exists in scripts/templates/ directory
- The systemd service files (power-monitor.service, wittypi-firstboot.service, wittypi-rtc-sync.service, wittypi-rtc-sync.timer) exist in scripts/templates/ directory
- INA219 power sensor is connected to I2C bus (typically address 0x40 or 0x41)
- System has at least 50MB of free disk space for WittyPi software and power logs (30 days of logs at 60-second sampling requires approximately 2MB)

## Dependencies *(optional)*

- **External Systems**: uugear.com website must be accessible for WittyPi software download
- **Hardware**: WittyPi 4 Mini HAT, INA219 current/voltage sensor, Raspberry Pi with I2C GPIO pins
- **System Packages**: i2c-tools, python3-smbus (installed by script)
- **Existing Services**: systemd, timedatectl, NTP/timesyncd for network time
- **Related Features**: Installation script infrastructure from vision-sensor (install.sh) and reference implementation from edge-sensor (install.sh)
