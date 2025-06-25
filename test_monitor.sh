#!/bin/bash

# Test script to run the monitor for a short duration
echo "Testing ADB Traffic Monitor for 5 seconds..."
echo "Please generate some network activity on your phone..."

# Run the monitor in background
./adb_traffic_monitor.sh &
MONITOR_PID=$!

# Wait 5 seconds
sleep 5

# Kill the monitor
kill $MONITOR_PID 2>/dev/null

echo "Test completed!"