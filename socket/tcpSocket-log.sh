#!/usr/bin/env bash

hst="info.cern.ch"
prt=80
cmd=$'GET / HTTP/1.0\r\nHost: info.cern.ch\r\n\r\n'

timeout_ms=1000
sleep_sec=3
summary=10
summary_log=200

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
log_file="${script_dir}/tcpSocket_failures.$$.log"
echo "LogFile: $log_file"

# Terminal color codes
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m' # No Color

i=0; fails=0; total_time=0; min=-1; max=0; summary_msg=""
since=$(date +"%Y-%m-%d %H:%M:%S")

while true; do
  if [ $((i % summary)) -eq 0 ]; then
    echo -e "${CYAN}Monitoring local netIPC connection [$summary_msg] Press Ctrl+C to stop.${NC}"
  fi

  i=$((i + 1))
  [ "$i" -gt 1 ] && sleep "$sleep_sec"

  # Record start time in milliseconds
  start_ms=$(date +%s%3N)
  time_stamp1=$(date +"%Y-%m-%d %H:%M:%S")
  log_msg=""

  # Execute runTest and capture exit code
  outp=$(echo -n "$cmd" | nc "$hst" "$prt" 2>&1)
  exit_code=$?
  outp=$(echo "$outp" | head -n 1 | tee /dev/tty)
  if [ "$exit_code" -ne 0 ] || (echo "$outp" | grep -q -v "OK"); then
    fails=$((fails + 1))
    log_msg="[$time_stamp1] i=$i Error: $outp"
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

  avg=$(( i == 0 ? 0 : total_time / i ))
  summary_msg="failures=$fails/$i avg=$avg max=$max min=$min since=$since"
  if [ $((i % summary_log)) -eq 0 ]; then
    echo "[$(date +"%Y-%m-%d %H:%M:%S")] $summary_msg" >> "$log_file"
  fi
done
