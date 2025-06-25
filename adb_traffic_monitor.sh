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

check_adb_connection() {
    if ! command -v adb &> /dev/null; then
        error "ADB command not found. Please install Android SDK platform-tools."
        exit 1
    fi
    
    local devices=$(adb devices | grep -c "device$" || true)
    if [ "$devices" -eq 0 ]; then
        error "No ADB devices connected. Please connect your Android device."
        exit 1
    elif [ "$devices" -gt 1 ]; then
        warn "Multiple devices detected. Using the first one."
    fi
    
    log "ADB device connected successfully"
}

get_network_stats() {
    local net_data=$(adb shell cat /proc/net/dev 2>/dev/null || echo "")
    local rx_bytes=0
    local tx_bytes=0
    
    # Try to find active interfaces in order of preference
    for interface in wlan0 wlan1 rmnet1 eth0; do
        local line=$(echo "$net_data" | grep "^ *$interface:" || echo "")
        if [ -n "$line" ]; then
            local temp_rx=$(echo "$line" | awk '{print $2}')
            local temp_tx=$(echo "$line" | awk '{print $10}')
            if [ "$temp_rx" -gt 0 ] || [ "$temp_tx" -gt 0 ]; then
                rx_bytes=$temp_rx
                tx_bytes=$temp_tx
                break
            fi
        fi
    done
    
    # Fallback: sum all active interfaces
    if [ "$rx_bytes" -eq 0 ] && [ "$tx_bytes" -eq 0 ]; then
        rx_bytes=$(echo "$net_data" | grep -E "wlan|rmnet|eth" | awk '{rx+=$2; tx+=$10} END {print rx+0}')
        tx_bytes=$(echo "$net_data" | grep -E "wlan|rmnet|eth" | awk '{rx+=$2; tx+=$10} END {print tx+0}')
    fi
    
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
    
    echo -e "${GREEN}Time: $current_time${NC}"
    echo -e "${GREEN}Download: $(format_bytes $rx_speed)${NC}"
    echo -e "${RED}Upload:   $(format_bytes $tx_speed)${NC}"
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
    prev_rx_bytes=$(echo $stats | cut -d' ' -f1)
    prev_tx_bytes=$(echo $stats | cut -d' ' -f2)
    
    sleep 1
    
    while true; do
        local stats=$(get_network_stats)
        local current_rx_bytes=$(echo $stats | cut -d' ' -f1)
        local current_tx_bytes=$(echo $stats | cut -d' ' -f2)
        
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