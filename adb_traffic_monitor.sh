#!/bin/bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

GRAPH_WIDTH=60
GRAPH_HEIGHT=15
MAX_SCALE=1000000  # 1MB/s default max scale

prev_rx_bytes=0
prev_tx_bytes=0
rx_history=()
tx_history=()

log() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

SELECTED_DEVICE=""

select_device() {
    local device_list=$(adb devices | grep "device$" | cut -f1)
    local devices=($device_list)
    local device_count=${#devices[@]}
    
    if [ "$device_count" -eq 0 ]; then
        error "No ADB devices connected. Please connect your Android device."
        exit 1
    elif [ "$device_count" -eq 1 ]; then
        SELECTED_DEVICE=${devices[0]}
        log "Using device: $SELECTED_DEVICE"
        return
    fi
    
    echo -e "${BLUE}Multiple devices detected:${NC}"
    for i in "${!devices[@]}"; do
        local device_info=$(adb -s "${devices[$i]}" shell getprop ro.product.model 2>/dev/null || echo "Unknown device")
        echo -e "${YELLOW}$((i+1)).${NC} ${devices[$i]} ($device_info)"
    done
    echo
    
    while true; do
        read -p "Select device number (1-$device_count): " selection
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "$device_count" ]; then
            SELECTED_DEVICE=${devices[$((selection-1))]}
            log "Selected device: $SELECTED_DEVICE"
            break
        else
            error "Invalid selection. Please enter a number between 1 and $device_count."
        fi
    done
}

check_adb_connection() {
    if ! command -v adb &> /dev/null; then
        error "ADB command not found. Please install Android SDK platform-tools."
        exit 1
    fi
    
    select_device
    log "ADB device connected successfully"
}

get_network_stats() {
    local net_data=$(adb -s "$SELECTED_DEVICE" shell cat /proc/net/dev 2>/dev/null || echo "")
    local rx_bytes=0
    local tx_bytes=0
    local active_interface=""
    
    # Extended list of mobile network interfaces (prioritize active ones first)
    local mobile_interfaces="rmnet1 rmnet_data0 rmnet_data1 rmnet_data2 rmnet_data3 rmnet_data4 rmnet_data5 rmnet_data6 rmnet_data7 rmnet0 rmnet2 rmnet3 rmnet4 rmnet5 rmnet6 rmnet7 ccmni0 ccmni1 ccmni2 ccmni3 pdp_ip0 pdp_ip1 pdp_ip2 ppp0 rndis0"
    local wifi_interfaces="wlan0 wlan1 wlan2"
    local other_interfaces="eth0 eth1 usb0"
    
    # Function to check interface and extract stats
    check_interface() {
        local interface=$1
        local line=$(echo "$net_data" | grep "^ *$interface:" || echo "")
        if [ -n "$line" ]; then
            local temp_rx=$(echo "$line" | awk '{print $2}')
            local temp_tx=$(echo "$line" | awk '{print $10}')
            # Check if interface has meaningful traffic (not just initialization bytes)
            if [ "$temp_rx" -gt 1000 ] || [ "$temp_tx" -gt 1000 ]; then
                rx_bytes=$temp_rx
                tx_bytes=$temp_tx
                active_interface=$interface
                return 0
            fi
        fi
        return 1
    }
    
    # Try mobile interfaces first (may be more active)
    for interface in $mobile_interfaces; do
        if check_interface "$interface"; then
            break
        fi
    done
    
    # If no mobile found, try Wi-Fi interfaces
    if [ "$rx_bytes" -eq 0 ] && [ "$tx_bytes" -eq 0 ]; then
        for interface in $wifi_interfaces; do
            if check_interface "$interface"; then
                break
            fi
        done
    fi
    
    # Try other interfaces as fallback
    if [ "$rx_bytes" -eq 0 ] && [ "$tx_bytes" -eq 0 ]; then
        for interface in $other_interfaces; do
            if check_interface "$interface"; then
                break
            fi
        done
    fi
    
    # Last resort: use /proc/net/xt_qtaguid/stats if available (Android-specific)
    if [ "$rx_bytes" -eq 0 ] && [ "$tx_bytes" -eq 0 ]; then
        local qtaguid_data=$(adb -s "$SELECTED_DEVICE" shell cat /proc/net/xt_qtaguid/stats 2>/dev/null | tail -n +2 || echo "")
        if [ -n "$qtaguid_data" ]; then
            rx_bytes=$(echo "$qtaguid_data" | awk '{rx+=$6} END {print rx+0}')
            tx_bytes=$(echo "$qtaguid_data" | awk '{tx+=$8} END {print tx+0}')
            active_interface="qtaguid"
        fi
    fi
    
    # Final fallback: sum all interfaces with significant traffic
    if [ "$rx_bytes" -eq 0 ] && [ "$tx_bytes" -eq 0 ]; then
        rx_bytes=$(echo "$net_data" | grep -E ":" | awk '$2 > 1000 {rx+=$2} END {print rx+0}')
        tx_bytes=$(echo "$net_data" | grep -E ":" | awk '$10 > 1000 {tx+=$10} END {print tx+0}')
        active_interface="aggregated"
    fi
    
    # Store active interface for debugging
    echo "ACTIVE_INTERFACE=$active_interface" > /tmp/adb_traffic_debug 2>/dev/null || true
    
    echo "$rx_bytes $tx_bytes"
}

format_bytes() {
    local bytes=$1
    if [ "$bytes" -gt 1048576 ]; then
        echo "$(( bytes / 1048576 )) MB/s"
    elif [ "$bytes" -gt 1024 ]; then
        echo "$(( bytes / 1024 )) KB/s"
    else
        echo "$bytes B/s"
    fi
}

draw_graph() {
    local -a data=("$@")
    local max_val=0
    
    for val in "${data[@]}"; do
        if [ "$val" -gt "$max_val" ]; then
            max_val=$val
        fi
    done
    
    if [ "$max_val" -eq 0 ]; then
        max_val=1
    fi
    
    if [ "$max_val" -gt "$MAX_SCALE" ]; then
        MAX_SCALE=$max_val
    fi
    
    for ((row = GRAPH_HEIGHT; row > 0; row--)); do
        local threshold=$(( MAX_SCALE * row / GRAPH_HEIGHT ))
        printf "%8s |" "$(format_bytes $threshold)"
        
        for val in "${data[@]}"; do
            if [ "$val" -ge "$threshold" ]; then
                printf "█"
            else
                printf " "
            fi
        done
        echo
    done
    
    printf "%8s +" "0"
    for ((i = 0; i < ${#data[@]}; i++)); do
        printf "-"
    done
    echo
}

display_traffic() {
    clear
    echo -e "${BLUE}=== ADB Traffic Monitor ===${NC}"
    echo
    
    local current_time=$(date '+%H:%M:%S')
    local rx_speed=0
    local tx_speed=0
    
    if [ ${#rx_history[@]} -gt 0 ]; then
        local last_index=$((${#rx_history[@]} - 1))
        rx_speed=${rx_history[$last_index]}
        tx_speed=${tx_history[$last_index]}
    fi
    
    # Show active interface for debugging
    local active_interface="unknown"
    if [ -f /tmp/adb_traffic_debug ]; then
        active_interface=$(grep "ACTIVE_INTERFACE" /tmp/adb_traffic_debug 2>/dev/null | cut -d'=' -f2 || echo "unknown")
    fi
    
    echo -e "${GREEN}Time: $current_time${NC}"
    echo -e "${GREEN}Download: $(format_bytes $rx_speed)${NC}"
    echo -e "${RED}Upload:   $(format_bytes $tx_speed)${NC}"
    echo -e "${YELLOW}Interface: $active_interface${NC}"
    echo
    
    if [ ${#rx_history[@]} -gt 0 ]; then
        echo -e "${GREEN}Download Traffic:${NC}"
        draw_graph "${rx_history[@]}"
        echo
        
        echo -e "${RED}Upload Traffic:${NC}"
        draw_graph "${tx_history[@]}"
    fi
    
    echo
    echo "Press Ctrl+C to stop monitoring..."
}

cleanup() {
    echo
    log "Stopping traffic monitor..."
    exit 0
}

main() {
    trap cleanup INT TERM
    
    log "Starting ADB Traffic Monitor..."
    check_adb_connection
    
    # Get initial values
    local stats=$(get_network_stats)
    prev_rx_bytes=$(echo "$stats" | cut -d' ' -f1)
    prev_tx_bytes=$(echo "$stats" | cut -d' ' -f2)
    
    
    sleep 1
    
    while true; do
        local stats=$(get_network_stats)
        local current_rx_bytes=$(echo "$stats" | cut -d' ' -f1)
        local current_tx_bytes=$(echo "$stats" | cut -d' ' -f2)
        
        local rx_speed=$(( current_rx_bytes - prev_rx_bytes ))
        local tx_speed=$(( current_tx_bytes - prev_tx_bytes ))
        
        
        if [ "$rx_speed" -lt 0 ]; then rx_speed=0; fi
        if [ "$tx_speed" -lt 0 ]; then tx_speed=0; fi
        
        rx_history+=($rx_speed)
        tx_history+=($tx_speed)
        
        if [ ${#rx_history[@]} -gt $GRAPH_WIDTH ]; then
            rx_history=("${rx_history[@]:1:$GRAPH_WIDTH}")
            tx_history=("${tx_history[@]:1:$GRAPH_WIDTH}")
        fi
        
        display_traffic
        
        prev_rx_bytes=$current_rx_bytes
        prev_tx_bytes=$current_tx_bytes
        
        sleep 1
    done
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi