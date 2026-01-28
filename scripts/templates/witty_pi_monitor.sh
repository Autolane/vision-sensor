#!/bin/bash

# Witty Pi 4 Mini Power Monitor with INA219 Battery Monitoring
# Tracks power consumption over 24 hours with 30-day data retention
# Compatible with Pi Zero 2W with 4S LiFePO4 battery (12.8V nominal)

# Configuration
SAMPLE_INTERVAL=60  # Sample every 60 seconds
LOG_FILE="/var/log/wittypi_power.log"
DATA_DIR="/tmp/power_monitor"
DAILY_DATA_DIR="/var/log/power_daily"
WITTYPI_ADDRESS="0x08"  # WittyPi for 5V supply monitoring
INA219_ADDRESS="0x40"   # INA219 for battery voltage monitoring
MAX_DAYS_RETENTION=30

# Battery Configuration (4S LiFePO4)
BATTERY_CELLS=4
BATTERY_FULL_VOLTAGE=13.6     # 3.4V per cell (practical charging max)
BATTERY_NOMINAL_VOLTAGE=12.8  # 3.2V per cell
BATTERY_LOW_VOLTAGE=12.4      # 3.1V per cell (20%)
BATTERY_CRITICAL_VOLTAGE=12.0 # 3.0V per cell (10%)

# Alert configuration
ALERT_LOG="/var/log/battery_alerts.log"
LAST_ALERT_FILE="/tmp/last_battery_alert"

# Create directories if they don't exist
mkdir -p "$DATA_DIR"
mkdir -p "$DAILY_DATA_DIR"

# Function to log messages with timestamp
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Function to log battery alerts
log_alert() {
    local message="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - ALERT: $message" | tee -a "$ALERT_LOG"
    log_message "ALERT: $message"
}

# Function to check if alert cooldown has passed (don't spam alerts)
should_send_alert() {
    local alert_type="$1"
    local cooldown_minutes=60  # Only alert once per hour

    if [ ! -f "$LAST_ALERT_FILE" ]; then
        echo "0" > "$LAST_ALERT_FILE"
        return 0
    fi

    local last_alert=$(cat "$LAST_ALERT_FILE" 2>/dev/null || echo "0")
    local current_time=$(date +%s)
    local time_diff=$((current_time - last_alert))

    if [ $time_diff -gt $((cooldown_minutes * 60)) ]; then
        echo "$current_time" > "$LAST_ALERT_FILE"
        return 0
    fi

    return 1
}

# Function to get battery voltage from INA219
get_battery_voltage() {
    # Use Python to read INA219 battery voltage
    python3 - <<EOF 2>/dev/null
import smbus
try:
    bus = smbus.SMBus(1)
    raw = bus.read_word_data($INA219_ADDRESS, 0x02)
    voltage_raw = ((raw & 0xFF) << 8) | ((raw & 0xFF00) >> 8)
    voltage = (voltage_raw >> 3) * 0.004
    print(f"{voltage:.3f}")
except:
    print("0")
EOF
}

# Function to calculate battery percentage for LiFePO4
calculate_battery_percentage() {
    local voltage=$1
    local percentage

    # LiFePO4 voltage curve (approximate)
    if (( $(echo "$voltage >= $BATTERY_FULL_VOLTAGE" | bc -l) )); then
        percentage=100
    elif (( $(echo "$voltage >= 13.2" | bc -l) )); then
        # 13.2V - 13.6V = 80-100%
        percentage=$(echo "scale=1; 80 + (($voltage - 13.2) / 0.4) * 20" | bc -l)
    elif (( $(echo "$voltage >= $BATTERY_NOMINAL_VOLTAGE" | bc -l) )); then
        # 12.8V - 13.2V = 40-60%
        percentage=$(echo "scale=1; 40 + (($voltage - $BATTERY_NOMINAL_VOLTAGE) / 0.4) * 20" | bc -l)
    elif (( $(echo "$voltage >= $BATTERY_LOW_VOLTAGE" | bc -l) )); then
        # 12.4V - 12.8V = 20-40%
        percentage=$(echo "scale=1; 20 + (($voltage - $BATTERY_LOW_VOLTAGE) / 0.4) * 20" | bc -l)
    elif (( $(echo "$voltage >= $BATTERY_CRITICAL_VOLTAGE" | bc -l) )); then
        # 12.0V - 12.4V = 10-20%
        percentage=$(echo "scale=1; 10 + (($voltage - $BATTERY_CRITICAL_VOLTAGE) / 0.4) * 10" | bc -l)
    elif (( $(echo "$voltage >= 11.2" | bc -l) )); then
        # 11.2V - 12.0V = 0-10%
        percentage=$(echo "scale=1; ($voltage - 11.2) / 0.8 * 10" | bc -l)
    else
        percentage=0
    fi

    echo "$percentage"
}

# Function to check battery health and send alerts
check_battery_alerts() {
    local battery_voltage=$1
    local battery_percent=$2

    if (( $(echo "$battery_voltage < $BATTERY_CRITICAL_VOLTAGE" | bc -l) )); then
        if should_send_alert "critical"; then
            log_alert "CRITICAL: Battery voltage at ${battery_voltage}V (${battery_percent}%) - System may shutdown soon!"
        fi
        return 2
    elif (( $(echo "$battery_voltage < $BATTERY_LOW_VOLTAGE" | bc -l) )); then
        if should_send_alert "low"; then
            log_alert "LOW BATTERY: Battery voltage at ${battery_voltage}V (${battery_percent}%) - Recharge recommended"
        fi
        return 1
    fi

    return 0
}

# Function to get current power consumption from Witty Pi I2C registers
get_current_power() {
    local voltage_int voltage_dec current_int current_dec
    local voltage current power

    # Read voltage (registers 3 and 4) - This is 5V supply voltage
    voltage_int=$(i2cget -y 1 "$WITTYPI_ADDRESS" 3 2>/dev/null)
    voltage_dec=$(i2cget -y 1 "$WITTYPI_ADDRESS" 4 2>/dev/null)

    # Read current (registers 5 and 6)
    current_int=$(i2cget -y 1 "$WITTYPI_ADDRESS" 5 2>/dev/null)
    current_dec=$(i2cget -y 1 "$WITTYPI_ADDRESS" 6 2>/dev/null)

    # Check if reads were successful
    if [ -z "$voltage_int" ] || [ -z "$voltage_dec" ] || [ -z "$current_int" ] || [ -z "$current_dec" ]; then
        return 1
    fi

    # Convert hex to decimal
    voltage_int=$((voltage_int))
    voltage_dec=$((voltage_dec))
    current_int=$((current_int))
    current_dec=$((current_dec))

    # Calculate actual values (voltage in volts, current in amps)
    voltage=$(echo "scale=3; $voltage_int + ($voltage_dec / 100)" | bc -l)
    current=$(echo "scale=3; $current_int + ($current_dec / 100)" | bc -l)
    power=$(echo "scale=3; $voltage * $current" | bc -l)

    # Validate power reading (Pi Zero 2W typically uses 0.4-3W)
    if (( $(echo "$power < 0.1 || $power > 10" | bc -l) )); then
        return 1
    fi

    echo "$power"
    return 0
}

# Function to get ambient temperature from Witty Pi (LM75B sensor on board)
# NOTE: This is the temperature of the Witty Pi board, NOT the battery temperature
get_temperature() {
    local temp_raw temp_celsius

    # Read temperature from register 50 (LM75B ambient temperature sensor)
    # Note: i2cget with 'w' returns bytes in SMBus order (LSB, MSB)
    temp_raw=$(i2cget -y 1 "$WITTYPI_ADDRESS" 50 w 2>/dev/null)

    if [ -z "$temp_raw" ]; then
        echo "0"
        return 1
    fi

    # Convert to decimal
    temp_raw=$((temp_raw))

    # Swap bytes: SMBus returns LSB first, but LM75B expects MSB first
    # Formula: swapped = ((raw & 0xFF) << 8) | ((raw >> 8) & 0xFF)
    temp_raw=$(( ((temp_raw & 0xFF) << 8) | ((temp_raw >> 8) & 0xFF) ))

    # Calculate temperature: LM75B format is 11-bit two's complement
    # Upper 11 bits contain the temperature value with 0.125°C resolution
    temp_celsius=$(echo "scale=1; $temp_raw / 256" | bc -l)

    echo "$temp_celsius"
    return 0
}

# Function to initialize daily tracking
init_daily_tracking() {
    local today=$(date '+%Y-%m-%d')
    local daily_file="$DAILY_DATA_DIR/power_$today.csv"

    if [ ! -f "$daily_file" ]; then
        echo "timestamp,power_watts,supply_voltage_volts,current_amps,battery_voltage_volts,battery_percent,ambient_temp_celsius,energy_wh,cumulative_wh" > "$daily_file"
        echo "0" > "$DAILY_DATA_DIR/total_$today.dat"
        log_message "Started new daily tracking file: $daily_file"
    fi

    echo "$daily_file"
}

# Function to add power sample and calculate energy
add_power_sample() {
    local power_watts=$1
    local supply_voltage=$2
    local current=$3
    local battery_voltage=$4
    local battery_percent=$5
    local temperature=$6
    local daily_file=$7
    local today=$(date '+%Y-%m-%d')
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Calculate energy for this interval (Wh)
    local interval_hours=$(echo "scale=6; $SAMPLE_INTERVAL / 3600" | bc -l)
    local energy_wh=$(echo "scale=6; $power_watts * $interval_hours" | bc -l)

    # Update cumulative total
    local total_file="$DAILY_DATA_DIR/total_$today.dat"
    local current_total=$(cat "$total_file" 2>/dev/null || echo "0")
    local new_total=$(echo "scale=6; $current_total + $energy_wh" | bc -l)
    echo "$new_total" > "$total_file"

    # Append to daily CSV (now includes battery voltage and percentage)
    echo "$timestamp,$power_watts,$supply_voltage,$current,$battery_voltage,$battery_percent,$temperature,$energy_wh,$new_total" >> "$daily_file"

    # Also maintain a rolling 24-hour file
    local rolling_file="$DATA_DIR/power_24h.csv"
    echo "$timestamp,$power_watts,$supply_voltage,$current,$battery_voltage,$battery_percent,$temperature,$energy_wh,$new_total" >> "$rolling_file"

    # Keep only last 24 hours of data in rolling file (1440 samples at 1-minute intervals)
    tail -n 1440 "$rolling_file" > "$rolling_file.tmp" && mv "$rolling_file.tmp" "$rolling_file"
}

# Function to cleanup old files
cleanup_old_files() {
    local cutoff_date=$(date -d "$MAX_DAYS_RETENTION days ago" '+%Y-%m-%d')

    # Remove files older than retention period
    find "$DAILY_DATA_DIR" -name "power_*.csv" -type f | while read -r file; do
        local file_date=$(basename "$file" | sed 's/power_\(.*\)\.csv/\1/')
        if [[ "$file_date" < "$cutoff_date" ]]; then
            rm -f "$file"
            rm -f "$DAILY_DATA_DIR/total_$file_date.dat"
            log_message "Removed old data file: $file"
        fi
    done
}

# Function to generate daily summary
generate_daily_summary() {
    local yesterday=$(date -d "yesterday" '+%Y-%m-%d')
    local daily_file="$DAILY_DATA_DIR/power_$yesterday.csv"
    local total_file="$DAILY_DATA_DIR/total_$yesterday.dat"

    if [ -f "$daily_file" ] && [ -f "$total_file" ]; then
        local total_wh=$(cat "$total_file")
        local total_kwh=$(echo "scale=6; $total_wh / 1000" | bc -l)
        local avg_power=$(tail -n +2 "$daily_file" | awk -F',' '{sum+=$2; count++} END {if(count>0) print sum/count; else print 0}')
        local max_power=$(tail -n +2 "$daily_file" | awk -F',' 'BEGIN{max=0} {if($2>max) max=$2} END {print max}')
        local min_power=$(tail -n +2 "$daily_file" | awk -F',' 'BEGIN{min=999} {if($2<min && $2>0) min=$2} END {print min}')
        local min_battery=$(tail -n +2 "$daily_file" | awk -F',' 'BEGIN{min=999} {if($5<min && $5>0) min=$5} END {print min}')
        local max_battery=$(tail -n +2 "$daily_file" | awk -F',' 'BEGIN{max=0} {if($5>max) max=$5} END {print max}')

        log_message "DAILY SUMMARY for $yesterday:"
        log_message "  Total Energy: ${total_wh} Wh (${total_kwh} kWh)"
        log_message "  Average Power: ${avg_power} W"
        log_message "  Peak Power: ${max_power} W"
        log_message "  Minimum Power: ${min_power} W"
        log_message "  Battery Voltage Range: ${min_battery}V - ${max_battery}V"

        # Create summary file
        local summary_file="$DAILY_DATA_DIR/summary_$yesterday.txt"
        cat > "$summary_file" << EOF
Daily Power Summary for $yesterday
=================================
Total Energy: ${total_wh} Wh (${total_kwh} kWh)
Average Power: ${avg_power} W
Peak Power: ${max_power} W
Minimum Power: ${min_power} W
Battery Voltage Range: ${min_battery}V - ${max_battery}V
Sample Count: $(tail -n +2 "$daily_file" | wc -l)
EOF
    fi
}

# Function to check Witty Pi connectivity
check_witty_pi() {
    local firmware_id

    # Check if i2c-tools is available
    if ! command -v i2cget &> /dev/null; then
        log_message "ERROR: i2c-tools not installed. Run: sudo apt-get install i2c-tools"
        return 1
    fi

    # Check if I2C is enabled
    if [ ! -e /dev/i2c-1 ]; then
        log_message "ERROR: I2C interface not enabled. Enable via raspi-config"
        return 1
    fi

    # Check Witty Pi firmware
    firmware_id=$(i2cget -y 1 "$WITTYPI_ADDRESS" 0 2>/dev/null)
    if [ "$firmware_id" != "0x36" ]; then
        log_message "ERROR: Witty Pi 4 Mini not detected at I2C address $WITTYPI_ADDRESS"
        log_message "Expected firmware ID 0x36, got: $firmware_id"
        return 1
    fi

    log_message "Witty Pi 4 Mini detected successfully (firmware ID: $firmware_id)"

    # Check INA219
    local ina219_test=$(i2cget -y 1 "$INA219_ADDRESS" 0x00 w 2>/dev/null)
    if [ -z "$ina219_test" ]; then
        log_message "ERROR: INA219 not detected at I2C address $INA219_ADDRESS"
        return 1
    fi

    log_message "INA219 battery monitor detected at $INA219_ADDRESS"

    return 0
}

# Main monitoring function
main() {
    log_message "Starting Witty Pi 4 Mini Power Monitor with INA219 Battery Monitoring"
    log_message "Sample interval: ${SAMPLE_INTERVAL}s, Data retention: ${MAX_DAYS_RETENTION} days"
    log_message "Battery: 4S LiFePO4 (${BATTERY_NOMINAL_VOLTAGE}V nominal, ${BATTERY_FULL_VOLTAGE}V charge max)"

    # Check prerequisites
    if ! check_witty_pi; then
        exit 1
    fi

    # Install dependencies if not present
    if ! command -v bc &> /dev/null; then
        log_message "Installing bc calculator..."
        apt-get update && apt-get install -y bc
    fi

    if ! python3 -c "import smbus" 2>/dev/null; then
        log_message "Installing python3-smbus..."
        apt-get update && apt-get install -y python3-smbus
    fi

    local last_date=""
    local failed_readings=0
    local max_failed_readings=5

    while true; do
        local current_date=$(date '+%Y-%m-%d')

        # Check if we've moved to a new day
        if [ "$current_date" != "$last_date" ]; then
            if [ ! -z "$last_date" ]; then
                generate_daily_summary
            fi
            cleanup_old_files
            last_date="$current_date"
        fi

        # Get battery voltage from INA219
        local battery_voltage
        battery_voltage=$(get_battery_voltage)

        if [ -z "$battery_voltage" ] || [ "$battery_voltage" = "0" ]; then
            log_message "WARNING: Failed to read battery voltage from INA219"
            battery_voltage="0.00"
        fi

        # Calculate battery percentage
        local battery_percent
        battery_percent=$(calculate_battery_percentage "$battery_voltage")

        # Check for battery alerts
        check_battery_alerts "$battery_voltage" "$battery_percent"
        local battery_status=$?

        # Get current power and other readings from WittyPi
        local current_power supply_voltage current temperature

        current_power=$(get_current_power)
        if [ $? -ne 0 ] || [ -z "$current_power" ]; then
            failed_readings=$((failed_readings + 1))
            log_message "WARNING: Failed to read power data (attempt $failed_readings/$max_failed_readings)"

            if [ $failed_readings -ge $max_failed_readings ]; then
                log_message "ERROR: Too many consecutive failed readings. Exiting."
                exit 1
            fi

            sleep "$SAMPLE_INTERVAL"
            continue
        fi

        # Get additional readings for logging (5V supply side)
        supply_voltage=$(echo "scale=2; $(i2cget -y 1 "$WITTYPI_ADDRESS" 3 2>/dev/null | xargs printf "%d") + ($(i2cget -y 1 "$WITTYPI_ADDRESS" 4 2>/dev/null | xargs printf "%d") / 100)" | bc -l 2>/dev/null || echo "0.00")
        current=$(echo "scale=2; $(i2cget -y 1 "$WITTYPI_ADDRESS" 5 2>/dev/null | xargs printf "%d") + ($(i2cget -y 1 "$WITTYPI_ADDRESS" 6 2>/dev/null | xargs printf "%d") / 100)" | bc -l 2>/dev/null || echo "0.00")
        temperature=$(get_temperature)

        # Reset failed reading counter on successful read
        failed_readings=0

        # Initialize or get daily tracking file
        local daily_file=$(init_daily_tracking)

        # Add power sample
        add_power_sample "$current_power" "$supply_voltage" "$current" "$battery_voltage" "$battery_percent" "$temperature" "$daily_file"

        # Get current daily total for display
        local today=$(date '+%Y-%m-%d')
        local daily_total=$(cat "$DAILY_DATA_DIR/total_$today.dat" 2>/dev/null || echo "0")
        local daily_kwh=$(echo "scale=6; $daily_total / 1000" | bc -l)

        # Display current status with battery information
        local current_hour=$(date '+%H')
        local current_minute=$(date '+%M')
        local operational_status

        if [ "$current_hour" -ge 9 ] && ([ "$current_hour" -lt 21 ] || ([ "$current_hour" -eq 21 ] && [ "$current_minute" -lt 30 ])); then
            operational_status="OPERATIONAL"
        else
            operational_status="SCHEDULED_OFF_SOON"
        fi

        # Color code battery status for display
        local battery_indicator
        if [ $battery_status -eq 2 ]; then
            battery_indicator="CRITICAL"
        elif [ $battery_status -eq 1 ]; then
            battery_indicator="LOW"
        else
            battery_indicator="OK"
        fi

        printf "\r\033[K$(date '+%H:%M:%S') - Power: %.3fW | Supply: %sV | Battery: %.2fV (%.0f%% %s) | Today: %.3f Wh | Status: %s" \
            "$current_power" "$supply_voltage" "$battery_voltage" "$battery_percent" "$battery_indicator" "$daily_total" "$operational_status"

        sleep "$SAMPLE_INTERVAL"
    done
}

# Signal handler for clean shutdown
cleanup_and_exit() {
    echo ""
    log_message "Power monitor stopped gracefully"
    generate_daily_summary
    exit 0
}

# Set up signal handlers
trap cleanup_and_exit SIGINT SIGTERM

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "This script should be run as root for I2C access"
    echo "Usage: sudo $0"
    exit 1
fi

# Start monitoring
main
