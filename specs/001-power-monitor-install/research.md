# Research: Power Monitor Installation

**Feature**: 001-power-monitor-install
**Date**: 2026-01-27
**Reference Implementation**: ../edge-sensor/scripts/install.sh

## Overview

This research document consolidates implementation patterns from the edge-sensor reference implementation for WittyPi 4 Mini power management and INA219 battery monitoring integration.

## Technology Decisions

### Decision 1: WittyPi Installation Strategy

**Decision**: Use official WittyPi installer from uugear.com, delegate I2C configuration to vendor script

**Rationale**:
- WittyPi installer handles all I2C enablement automatically (/boot/config.txt, /etc/modules, kernel module blacklist removal)
- Vendor-maintained script ensures compatibility with latest Raspberry Pi OS versions
- Reduces maintenance burden - no need to track I2C configuration changes across OS updates
- Proven reliable in edge-sensor production deployments (800+ installations)

**Implementation Pattern**:
```bash
WITTYPI_URL="https://www.uugear.com/repo/WittyPi4/install.sh"
WITTYPI_DIR="/opt/wittypi"

# Download and run official installer
cd "$WITTYPI_DIR"
wget -q "$WITTYPI_URL" -O install.sh
sh install.sh 2>&1 | tee /tmp/wittypi_install.log

# Verify installation
[ -f "$WITTYPI_DIR/wittypi/utilities.sh" ] || { log_warn "Installation incomplete"; return 0; }
```

**Alternatives Considered**:
- Manual I2C configuration (rejected: fragile, requires tracking multiple file changes)
- Python WittyPi library (rejected: unnecessary dependency, bash utilities.sh sufficient)

---

### Decision 2: RTC Synchronization Architecture

**Decision**: Three-tier RTC sync strategy (first-boot NTP, shutdown sync, daily timer)

**Rationale**:
- **First-boot NTP sync**: Ensures RTC initialized with accurate internet time on deployment
- **Shutdown sync**: Preserves accurate time when device powered off (system → RTC)
- **Daily timer**: Corrects RTC drift over time (~1-2 seconds/day typical crystal oscillator drift)
- **Boot sync**: Handled automatically by WittyPi daemon (RTC → system when network unavailable)

**Implementation Pattern**:

1. **One-shot first-boot service** (`wittypi-firstboot.service`):
   - Waits up to 30 seconds for NTP sync
   - Sources `/opt/wittypi/wittypi/utilities.sh` for `system_to_rtc` function
   - Enables auto-boot via I2C register write (0x11 = 0x01)
   - Self-removes after successful configuration

2. **Shutdown sync service** (`wittypi-rtc-sync.service`):
   - Triggers Before=shutdown.target reboot.target halt.target
   - Executes `system_to_rtc` to preserve system time to RTC

3. **Daily timer** (`wittypi-rtc-sync.timer` + `wittypi-rtc-sync-daily.service`):
   - OnCalendar=daily
   - Persistent=true (runs missed executions after boot)

**Alternatives Considered**:
- Hourly sync (rejected: unnecessary overhead, RTC drift is slow)
- Manual sync only (rejected: RTC would drift significantly over weeks)
- NTP-only with no RTC (rejected: requires constant network, violates edge-first principle)

---

### Decision 3: Power Monitoring Implementation

**Decision**: Bash script with embedded Python for INA219, 60-second sampling to CSV files

**Rationale**:
- **Bash**: Lightweight, no runtime dependencies beyond system packages
- **Embedded Python**: Only for INA219 smbus access (not available in bash)
- **60-second sampling**: Balances data granularity with storage efficiency (~2MB/30 days)
- **CSV format**: Human-readable, easily imported into analysis tools (Excel, pandas)
- **30-day retention**: Provides monthly trend analysis within constrained storage

**Data Collection**:
- WittyPi metrics via i2cget (5V supply voltage, current, temperature)
- INA219 battery voltage via Python smbus (address 0x40, register 0x02)
- Energy calculation: Power (W) × Interval (h) = Energy (Wh)
- Cumulative daily tracking in separate .dat file

**CSV Schema**:
```csv
timestamp,power_watts,supply_voltage_volts,current_amps,battery_voltage_volts,battery_percent,ambient_temp_celsius,energy_wh,cumulative_wh
```

**Alternatives Considered**:
- JSON format (rejected: larger file size, less human-readable)
- SQLite database (rejected: adds dependency, increases complexity)
- 5-second sampling (rejected: 17K samples/day, excessive for power trend analysis)
- Syslog integration (rejected: log rotation complexity, harder to query time-series data)

---

### Decision 4: Service Restart and Error Handling

**Decision**: Automatic restart with 10-second delay, non-fatal installation errors

**Rationale**:
- **10-second RestartSec**: Prevents rapid crash loops while allowing quick recovery from transient failures (I2C glitches)
- **Restart=always**: Self-healing for embedded systems (matches constitution Principle III)
- **Non-fatal installation**: Continue with degraded functionality when optional hardware unavailable (field deployment resilience)
- **Warning logs**: Actionable error messages for remote diagnosis

**Service Configuration**:
```ini
[Service]
Type=simple
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
```

**Installation Error Handling**:
```bash
configure_wittypi() {
    # Non-fatal errors - log warning and continue
    if ! wget -q "$WITTYPI_URL" -O install.sh; then
        log_warn "Failed to download WittyPi installer"
        return 0  # Continue installation
    fi

    # Verify but don't block
    if [ ! -d "$WITTYPI_DIR/wittypi" ]; then
        log_warn "WittyPi directory not found - skipping configuration"
        return 0
    fi
}
```

**Alternatives Considered**:
- Immediate restart (rejected: could cause CPU thrashing during persistent failures)
- Manual restart only (rejected: requires human intervention, violates edge-first principle)
- Installation rollback on failure (rejected: partial success is valuable in field deployments)

---

### Decision 5: Power Schedule Management

**Decision**: .wpi file format processed by WittyPi's runScript.sh

**Rationale**:
- **Vendor format**: Uses WittyPi's native schedule format (BEGIN/END/ON/OFF)
- **Local time interpretation**: Schedule times in system timezone (7 AM local, not UTC)
- **runScript.sh processing**: Calculates next wake time, writes to I2C registers
- **Template + active pattern**: Copy to schedules/ (template) and schedule.wpi (active)

**Schedule File** (`daily_7am_to_930pm.wpi`):
```
BEGIN   2024-11-04 21:30:00
END     2035-12-31 23:59:59
OFF     H9 M30    # 9h 30m off (9:30 PM to 7:00 AM)
ON      H14 M30   # 14h 30m on (7:00 AM to 9:30 PM)
```

**Processing Pattern**:
```bash
# Copy as template
cp daily_7am_to_930pm.wpi "$WITTYPI_DIR/wittypi/schedules/"

# Activate schedule
cp daily_7am_to_930pm.wpi "$WITTYPI_DIR/wittypi/schedule.wpi"

# Process (sets I2C wake registers)
cd "$WITTYPI_DIR/wittypi"
bash runScript.sh >> schedule.log 2>&1
```

**Alternatives Considered**:
- Cron-based scheduling (rejected: doesn't control hardware power, only software)
- Custom I2C register programming (rejected: duplicates vendor logic, maintenance burden)
- UTC timestamps (rejected: confusing for field deployments, requires timezone math)

---

### Decision 6: Log Retention Implementation

**Decision**: Daily midnight cleanup, find-based file age detection, 30-day retention

**Rationale**:
- **Midnight trigger**: Detected via date change in main loop (no external scheduler needed)
- **find + date comparison**: Portable, handles edge cases (daylight saving, leap years)
- **30-day window**: Balances historical analysis with storage constraints (~2MB total)
- **Cleanup before summary**: Ensures old files removed before generating previous day's summary

**Implementation**:
```bash
cleanup_old_files() {
    local cutoff_date=$(date -d "$MAX_DAYS_RETENTION days ago" '+%Y-%m-%d')

    find "$DAILY_DATA_DIR" -name "power_*.csv" -type f | while read -r file; do
        local file_date=$(basename "$file" | sed 's/power_\(.*\)\.csv/\1/')

        if [[ "$file_date" < "$cutoff_date" ]]; then
            rm -f "$file"
            rm -f "$DAILY_DATA_DIR/total_$file_date.dat"
            rm -f "$DAILY_DATA_DIR/summary_$file_date.txt"
        fi
    done
}
```

**Alternatives Considered**:
- logrotate integration (rejected: adds dependency, overkill for simple CSV cleanup)
- 7-day retention (rejected: too short for monthly pattern analysis)
- 90-day retention (rejected: ~6MB storage, excessive for operational monitoring)

---

## I2C Register Reference

### WittyPi 4 Mini Register Map

| Register | Address | Purpose | Values |
|----------|---------|---------|--------|
| Firmware ID | 0x00 | Device identification | 0x36 (WittyPi 4 Mini) |
| Supply Voltage (int) | 0x03 | 5V supply integer part | 0-255 (volts) |
| Supply Voltage (dec) | 0x04 | 5V supply decimal part | 0-99 (hundredths) |
| Current (int) | 0x05 | Current integer part | 0-255 (amps) |
| Current (dec) | 0x06 | Current decimal part | 0-99 (hundredths) |
| Auto-boot Config | 0x11 | Boot-on-power behavior | 0x00=off, 0x01=on |
| Temperature | 0x50 | LM75B ambient sensor | Raw value / 256 = °C |

### INA219 Battery Monitor

| Register | Address | Purpose | Calculation |
|----------|---------|---------|-------------|
| Bus Voltage | 0x02 | Battery voltage | `(raw >> 3) * 0.004` volts |

**I2C Bus**: `/dev/i2c-1` (bus 1 on Raspberry Pi)

---

## File Locations Summary

```
/opt/wittypi/wittypi/
├── utilities.sh                # I2C functions (source this)
├── schedule.wpi                # Active schedule
├── schedules/                  # Schedule templates
│   └── daily_7am_to_930pm.wpi
└── schedule.log                # Processing log

/opt/power-monitor/
└── witty_pi_monitor.sh         # Monitoring script

/var/log/power_daily/
├── power_YYYY-MM-DD.csv        # Daily samples
├── total_YYYY-MM-DD.dat        # Daily energy total
└── summary_YYYY-MM-DD.txt      # Human-readable summary

/etc/systemd/system/
├── wittypi-firstboot.service   # One-shot configuration
├── wittypi-rtc-sync.service    # Shutdown sync
├── wittypi-rtc-sync.timer      # Daily timer
└── power-monitor.service       # Continuous monitoring
```

---

## Best Practices Extracted

1. **Source utilities.sh before I2C operations**: Provides `system_to_rtc`, `i2c_read`, `i2c_write` functions
2. **Run runScript.sh from WittyPi directory**: Script expects to find schedule.wpi in current directory
3. **Wait 2 seconds after I2C writes**: Hardware register updates may lag
4. **Verify I2C operations**: Read back registers to confirm writes succeeded
5. **Use journalctl for service logs**: StandardOutput=journal enables `journalctl -u power-monitor -f`
6. **Non-blocking installation**: Optional components fail gracefully with warnings
7. **Hardware detection before operations**: Check firmware ID (0x36) before assuming WittyPi present
8. **Battery voltage validation**: Reject readings outside expected range (11V-14V for 4S LiFePO4)

---

## Constitution Compliance Notes

- **Edge-First**: RTC operates offline, NTP sync is opportunistic (30s timeout)
- **Resource Constraints**: 60s sampling = ~5MB RAM, ~2MB storage/30 days
- **Reliability**: Automatic restart, non-fatal installation errors, graceful degradation
- **Security**: No new network-facing services, root required for I2C hardware access
- **Observability**: Structured CSV logs, systemd journal integration, daily summaries
