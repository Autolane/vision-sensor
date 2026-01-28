# Quickstart Guide: Power Monitor Installation

**Feature**: 001-power-monitor-install
**Branch**: `001-power-monitor-install`
**Date**: 2026-01-27

## Overview

This guide provides step-by-step instructions for testing and validating the power monitor installation feature on Raspberry Pi hardware with WittyPi 4 Mini and INA219 components.

---

## Prerequisites

### Hardware Required

- **Raspberry Pi** (Zero 2W, 3, 4, or 5)
- **WittyPi 4 Mini HAT** (mounted on GPIO pins)
- **INA219 Current/Voltage Sensor** (connected to I2C bus at address 0x40)
- **Battery Pack** (4S LiFePO4, 12V nominal, 11-14V range)
- **MicroSD Card** (16GB minimum, Raspberry Pi OS installed)
- **Network Connection** (WiFi or Ethernet for initial setup)

### Software Required

- **Raspberry Pi OS** (Bookworm or newer, Debian-based with systemd)
- **Root Access** (`sudo` privileges)
- **Internet Connectivity** (for downloading WittyPi software and packages)

---

## Installation Steps

### Step 1: Clone Repository

```bash
cd ~
git clone <repository-url> vision-sensor
cd vision-sensor
git checkout 001-power-monitor-install
```

### Step 2: Prepare Installation Files

Copy required templates to scripts directory:

```bash
cd scripts

# Copy service templates
cp ../specs/001-power-monitor-install/contracts/power-monitor.service templates/
cp ../specs/001-power-monitor-install/contracts/wittypi-firstboot.service templates/
cp ../specs/001-power-monitor-install/contracts/wittypi-rtc-sync.service templates/
cp ../specs/001-power-monitor-install/contracts/wittypi-rtc-sync.timer templates/
cp ../specs/001-power-monitor-install/contracts/wittypi-rtc-sync-daily.service templates/

# Copy monitoring script (from edge-sensor reference)
cp /home/chadagate/edge-sensor/scripts/witty_pi_monitor.sh templates/

# Copy power schedule (from edge-sensor reference)
cp /home/chadagate/edge-sensor/scripts/daily_7am_to_930pm.wpi templates/
```

### Step 3: Run Installation Script

```bash
cd scripts
sudo ./install.sh
```

**Follow prompts**:
- Enter hostname (e.g., `vision-sensor-001`)
- Enter admin username (default: `admin`)
- Enter admin password (minimum 6 characters)
- Confirm configuration and proceed

**Expected Output**:
```
[INFO] Installing system packages...
[INFO] ✓ System packages installed
[INFO] Creating user and directories...
[INFO] ✓ Created vision-sensor user
[INFO] Installing and configuring WittyPi 4 Mini...
[INFO] ✓ WittyPi software installed to /opt/wittypi
[INFO] ✓ WittyPi first-boot configuration service enabled
[INFO] ✓ RTC sync services enabled
[INFO] ✓ Power schedule installed: 7:00 AM to 9:30 PM daily
[INFO] Installing power monitoring service...
[INFO] ✓ python3-smbus installed
[INFO] ✓ Power monitor service started
========================================
  Vision Sensor Installation Complete
========================================
Hostname: vision-sensor-001
WittyPi 4 Mini: Installed
  First-Boot Config: Pending (will run after reboot)
  RTC Status: Not yet synced
  Power Schedule: 7:00 AM to 9:30 PM local time
Power Monitor: Running
  Service Status: active
  Data Directory: /var/log/power_daily

⚠️  REBOOT REQUIRED:
  WittyPi configuration requires reboot
  sudo reboot
========================================
```

### Step 4: Reboot and Verify

```bash
sudo reboot
```

**Wait 2-3 minutes for system to boot and run first-boot service.**

---

## Verification and Testing

### Test 1: WittyPi Auto-Boot Verification

**Objective**: Confirm auto-boot is enabled (FR-005)

```bash
# Check first-boot service status (should be gone after successful run)
systemctl status wittypi-firstboot.service
# Expected: Unit wittypi-firstboot.service could not be found.

# View first-boot logs
journalctl -u wittypi-firstboot -n 50
# Expected: "✓ Auto-boot verified as ON", "✓ Configuration complete and service removed"

# Manually verify I2C register
cd /opt/wittypi/wittypi
source utilities.sh
i2c_read 0x01 $I2C_MC_ADDRESS $I2C_CONF_DEFAULT_ON
# Expected output: 0x01 (hex) or 1 (decimal)
```

**Success Criteria (SC-002)**: Device automatically powers on within 5 seconds of power restoration

**Test Procedure**:
1. Shutdown system: `sudo shutdown -h now`
2. Wait for complete power-off (LED off)
3. Remove power (unplug USB or battery disconnect)
4. Wait 10 seconds
5. Restore power
6. **Verify**: System boots automatically without button press within 5 seconds

---

### Test 2: RTC Time Synchronization

**Objective**: Confirm RTC sync mechanisms work (FR-004, FR-008, FR-009)

```bash
# Check RTC sync on shutdown service
systemctl status wittypi-rtc-sync.service
# Expected: loaded, enabled

# Check daily RTC sync timer
systemctl status wittypi-rtc-sync.timer
# Expected: active (waiting), enabled
systemctl list-timers wittypi-rtc-sync.timer
# Expected: shows next trigger time (tomorrow at midnight)

# Compare system time and RTC time
cd /opt/wittypi/wittypi
source utilities.sh
echo "System time: $(get_sys_time)"
echo "RTC time: $(get_rtc_time)"
# Expected: Times match within ~2 seconds
```

**Success Criteria (SC-008)**: RTC time synchronization completes within 35 seconds when NTP available

**Test Procedure**:
```bash
# Trigger first-boot service manually (if still exists)
sudo systemctl start wittypi-firstboot.service
journalctl -u wittypi-firstboot -f

# Expected log sequence:
# "Waiting for NTP sync (up to 30 seconds)..."
# "NTP sync complete after <N> seconds"  (N < 30)
# "Syncing system time to RTC..."
# Time shown completing within 35 seconds total
```

---

### Test 3: Power Monitoring Service

**Objective**: Verify power data collection (FR-021, FR-024)

```bash
# Check power monitor service status
systemctl status power-monitor.service
# Expected: active (running), enabled

# View recent logs
journalctl -u power-monitor -n 20
# Expected: No errors, battery voltage readings, power readings

# Check data files exist
ls -lh /var/log/power_daily/
# Expected: power_YYYY-MM-DD.csv, total_YYYY-MM-DD.dat files for today

# View latest power sample
tail -n 1 /var/log/power_daily/power_$(date +%Y-%m-%d).csv
# Expected: CSV row with 9 columns, recent timestamp
```

**Success Criteria (SC-004)**: Power monitor service logs voltage, current, and power readings every 60 seconds

**Test Procedure**:
```bash
# Monitor live updates
tail -f /var/log/power_daily/power_$(date +%Y-%m-%d).csv

# Expected: New line appears every 60 seconds with:
# - Timestamp (current time)
# - Power (0.1-10W range)
# - Voltage (~5V)
# - Current (0.05-3A)
# - Battery voltage (11-14V)
# - Battery percent (0-100%)
# - Temperature (-40 to 85°C)
# - Energy (Wh)
# - Cumulative (Wh)

# Press Ctrl+C to stop monitoring
```

---

### Test 4: Service Restart Policy

**Objective**: Verify automatic restart on failure (FR-022, SC-009)

```bash
# Manually kill power monitor service
sudo killall witty_pi_monitor.sh

# Wait 15 seconds
sleep 15

# Check if service restarted
systemctl status power-monitor.service
# Expected: active (running), with recent restart timestamp

# Check restart count
systemctl show power-monitor.service -p NRestarts
# Expected: NRestarts=1 (or higher if tested multiple times)

# View restart logs
journalctl -u power-monitor -n 50 | grep -i restart
# Expected: "Stopped WittyPi Power Monitor...", "Started WittyPi Power Monitor..." with ~10s gap
```

**Success Criteria (SC-009)**: Power monitor service automatically restarts within 15 seconds of failure (10-second delay + startup time)

---

### Test 5: Power Schedule Validation

**Objective**: Confirm schedule is installed and processed (FR-011, FR-012)

```bash
# Check if schedule file exists
ls -lh /opt/wittypi/wittypi/schedule.wpi
# Expected: File exists, ~200 bytes

# View schedule content
cat /opt/wittypi/wittypi/schedule.wpi
# Expected:
# BEGIN   2024-11-04 21:30:00
# END     2035-12-31 23:59:59
# OFF     H9 M30
# ON      H14 M30

# Check schedule processing log
tail -n 20 /opt/wittypi/wittypi/schedule.log
# Expected: "Next startup at...", "Next shutdown at..." entries

# Query WittyPi for next power cycle times
cd /opt/wittypi/wittypi
./wittyPi.sh
# Interactive menu: Select option to view next startup/shutdown times
# Expected: Shows 7:00 AM next startup, 9:30 PM next shutdown (local time)
```

**Success Criteria (SC-005)**: Device powers on at 7:00 AM local time (±2 minutes) and powers off at 9:30 PM local time (±2 minutes)

**Long-Term Test** (requires overnight monitoring):
1. Leave device powered and running
2. Note time approaching 9:30 PM
3. **Verify**: System shuts down automatically at 9:30 PM ±2 minutes
4. **Verify**: System powers on automatically at 7:00 AM ±2 minutes next morning

---

### Test 6: Log Rotation and Retention

**Objective**: Confirm old logs are deleted (FR-024, SC-010)

```bash
# Check current log files
ls -lt /var/log/power_daily/ | head -10
# Expected: Most recent files at top

# Manually create old log files for testing
sudo touch /var/log/power_daily/power_2024-01-01.csv
sudo touch /var/log/power_daily/total_2024-01-01.dat
sudo touch /var/log/power_daily/summary_2024-01-01.txt

# Wait for midnight (or trigger cleanup manually)
# The monitoring script checks for day change and runs cleanup

# Verify old files removed (next day)
ls /var/log/power_daily/ | grep "2024-01-01"
# Expected: No results (files deleted)
```

**Success Criteria (SC-010)**: Power log files older than 30 days are automatically deleted from /var/log/power_daily

**Accelerated Test**:
```bash
# Edit MAX_DAYS_RETENTION in monitoring script temporarily
sudo nano /opt/power-monitor/witty_pi_monitor.sh
# Change: MAX_DAYS_RETENTION=30 to MAX_DAYS_RETENTION=1

# Restart service
sudo systemctl restart power-monitor.service

# Create yesterday's file
yesterday=$(date -d "yesterday" +%Y-%m-%d)
sudo touch /var/log/power_daily/power_$yesterday.csv

# Wait for midnight rollover
# Or manually trigger by changing system date (not recommended)

# Verify deletion
ls /var/log/power_daily/ | grep "$yesterday"
# Expected: File deleted

# Restore original retention period
sudo nano /opt/power-monitor/witty_pi_monitor.sh
# Change back to: MAX_DAYS_RETENTION=30
sudo systemctl restart power-monitor.service
```

---

### Test 7: Graceful Degradation (No Hardware)

**Objective**: Verify installation continues when WittyPi not connected (FR-025, SC-007)

**Test Procedure** (on clean system without WittyPi):
```bash
# Ensure WittyPi hardware is NOT connected
# Run installation
sudo ./install.sh

# Expected output includes warnings:
# [WARN] No modem detected - may initialize after reboot
# [WARN] WittyPi hardware not detected - skipping configuration
# [INFO] Installation complete (with warnings)

# Verify installation completed
systemctl status vision-sensor.service
# Expected: active (running)

# Verify WittyPi services were NOT created
systemctl status wittypi-firstboot.service
# Expected: Unit could not be found (service not created)

# Verify power monitor service was NOT started
systemctl status power-monitor.service
# Expected: Unit could not be found OR failed (hardware detection)
```

**Success Criteria (SC-007)**: Installation script completes successfully with appropriate warnings when optional components fail

---

## Troubleshooting

### Issue: First-Boot Service Fails

**Symptoms**: `wittypi-firstboot.service` shows failed status

**Diagnosis**:
```bash
journalctl -u wittypi-firstboot -n 100
```

**Common Causes**:
- NTP sync timeout (network unavailable) → Check network connectivity
- utilities.sh not found → Verify WittyPi installed to /opt/wittypi
- I2C not enabled → Check /boot/firmware/config.txt for `dtparam=i2c_arm=on`
- Hardware not responding → Check WittyPi HAT seated correctly on GPIO pins

**Resolution**:
```bash
# Manually re-run first-boot configuration
sudo systemctl start wittypi-firstboot.service
journalctl -u wittypi-firstboot -f
```

---

### Issue: Power Monitor Service Won't Start

**Symptoms**: `power-monitor.service` shows failed/inactive

**Diagnosis**:
```bash
journalctl -u power-monitor -n 50
```

**Common Causes**:
- WittyPi not detected → Check firmware ID register
- INA219 not responding → Check I2C address 0x40
- python3-smbus not installed → Install with `sudo apt install python3-smbus`
- Permission denied on /var/log/power_daily → Check directory permissions

**Resolution**:
```bash
# Test WittyPi detection
cd /opt/wittypi/wittypi
source utilities.sh
i2c_read 0x01 0x08 0x00
# Expected: 0x36 (WittyPi 4 Mini firmware ID)

# Test INA219 detection
i2cdetect -y 1
# Expected: 40 visible in grid (INA219 address)

# Manually run monitoring script
sudo bash -x /opt/power-monitor/witty_pi_monitor.sh
# View detailed error output
```

---

### Issue: RTC Time Drifts

**Symptoms**: RTC time diverges from system time by minutes/hours

**Diagnosis**:
```bash
cd /opt/wittypi/wittypi
source utilities.sh
get_sys_time
get_rtc_time
# Compare values
```

**Resolution**:
```bash
# Manually sync system to RTC
cd /opt/wittypi/wittypi
source utilities.sh
system_to_rtc

# Verify sync
sleep 2
get_rtc_time

# Check daily sync timer is running
systemctl status wittypi-rtc-sync.timer
systemctl list-timers | grep wittypi
```

---

### Issue: Power Schedule Not Working

**Symptoms**: Device doesn't power off/on at scheduled times

**Diagnosis**:
```bash
cat /opt/wittypi/wittypi/schedule.log
# Check for processing errors
```

**Resolution**:
```bash
# Re-process schedule manually
cd /opt/wittypi/wittypi
bash runScript.sh

# Check for errors in schedule.log
tail -n 20 schedule.log

# Verify schedule file format
cat schedule.wpi
# Ensure BEGIN/END/OFF/ON lines present with correct syntax
```

---

## Data Analysis Examples

### View Current Power Consumption

```bash
tail -n 1 /var/log/power_daily/power_$(date +%Y-%m-%d).csv | cut -d',' -f2
# Output: 1.234 (watts)
```

### Plot Battery Voltage Trend (Last Hour)

```bash
tail -n 60 /var/log/power_daily/power_$(date +%Y-%m-%d).csv | \
    awk -F',' '{print $1, $5}' | \
    gnuplot -p -e 'set timefmt "%Y-%m-%d %H:%M:%S"; set xdata time; plot "-" using 1:2 with lines title "Battery Voltage"'
```

### Calculate Average Daily Power

```bash
tail -n +2 /var/log/power_daily/power_$(date +%Y-%m-%d).csv | \
    awk -F',' '{sum+=$2; count++} END {print "Average Power:", sum/count, "W"}'
```

### Export Last 7 Days to CSV

```bash
for i in {0..6}; do
    date=$(date -d "$i days ago" +%Y-%m-%d)
    cat /var/log/power_daily/power_$date.csv 2>/dev/null
done > last_7_days.csv
```

---

## Next Steps

After successful validation:

1. **Generate Tasks**: Run `/speckit.tasks` to create implementation task breakdown
2. **Begin Implementation**: Follow task sequence in `tasks.md`
3. **Hardware Testing**: Deploy to production hardware for field validation
4. **Monitor in Production**: Track power metrics, battery health, and schedule adherence

---

## Support

- **Specification**: [spec.md](./spec.md)
- **Implementation Plan**: [plan.md](./plan.md)
- **Data Model**: [data-model.md](./data-model.md)
- **Service Contracts**: [contracts/](./contracts/)
- **Logs**: `journalctl -u power-monitor -f`, `journalctl -u wittypi-firstboot -n 100`
