#!/usr/bin/env bash

target="8.8.8.8"
timeout_ms=1000
sleep_sec=1
summary=10
summary_log=200

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_file="${script_dir}/ping_failures.$$.log"
echo "LogFile: $log_file"

# Terminal color codes
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

i=0; fails=0; total_time=0; min=-1; max=0; summary_msg="" 
since=$(date +"%Y-%m-%d %H:%M:%S")

while true; do
  if [ $((i % summary)) -eq 0 ]; then
    echo -e "${CYAN}Monitoring pings to $target [$summary_msg] Press Ctrl+C to stop.${NC}"
  fi

  i=$((i + 1))
  [ "$i" -gt 1 ] && sleep "$sleep_sec"

  # Record start time in milliseconds
  start_ms=$(date +%s%3N)
  time_stamp1=$(date +"%Y-%m-%d %H:%M:%S")
  log_msg=""

  # Execute runTest and capture exit code
  # ping -c 1 -W 1 8.8.8.8 2>&1
  outp=$(ping -c 1 -W $(((timeout_ms + 999) / 1000)) $target 2>&1)
  exit_code=$?
  outp1=$(echo "$outp" | grep " from " | tee /dev/tty)
  if [ "$exit_code" -ne 0 ] || [ -z "$outp1" ]; then
    fails=$((fails + 1))
    outp1=$(echo "$outp" | tail -n 1)
    log_msg="[$time_stamp1] i=$i Error: $outp1"
    echo -e "${RED}${log_msg}${NC}"
    echo "$log_msg" >> "$log_file"
  fi

  # Record end time and calculate duration in ms
  end_ms=$(date +%s%3N)
  duration=$((end_ms - start_ms))
  total_time=$((total_time + duration))

  if [ "$duration" -gt "$max" ]; then
    max=$duration
  fi

  if [ "$min" -lt 0 ] || [ "$duration" -lt "$min" ]; then
    min=$duration
  fi

  echo "[$time_stamp1] i=$i time=${duration}ms"

  if [ "$duration" -gt "$timeout_ms" ]; then
    if [ -z "$log_msg" ]; then
      fails=$((fails + 1))
    fi
    time_stamp2=$(date +"%Y-%m-%d %H:%M:%S")
    log_msg="[$time_stamp2] Last attempt i=$i totalTime=${duration}ms exceeded ${timeout_ms}ms"
    echo -e "${RED}${log_msg}${NC}"
    echo "$log_msg" >> "$log_file"
  fi

  [ "$i" -eq 0 ] && avg=0 || avg=$((total_time / i))
  summary_msg="failures=$fails/$i avg=$avg max=$max min=$min since=$since"
  if [ $((i % summary_log)) -eq 0 ]; then
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $summary_msg" >> "$log_file"
  fi
done
