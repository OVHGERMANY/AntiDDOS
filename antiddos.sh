#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_CONFIG="$SCRIPT_DIR/config/antiddos.conf"
CONFIG_FILE="${ANTIDDOS_CONFIG:-$DEFAULT_CONFIG}"

# shellcheck disable=SC1090
load_config() {
  if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Config file not found: $CONFIG_FILE"
    echo "Copy config/antiddos.conf.example to config/antiddos.conf and edit values."
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"

  : "${INTERFACE:=eth0}"
  : "${POLL_INTERVAL:=2}"
  : "${RX_THRESHOLD_BYTES:=20000000}"
  : "${CONNECTION_THRESHOLD:=250}"
  : "${MONITORED_PORTS:=80,443}"
  : "${WHITELISTED_IPS:=}"
  : "${STATE_DIR:=/var/lib/antiddos}"
  : "${SIMULATE_LOG:=}"
}

state_init() {
  mkdir -p "$STATE_DIR"
  touch "$STATE_DIR/blocked_ips.txt" "$STATE_DIR/detections.log" "$STATE_DIR/counters.env"
  if [[ ! -s "$STATE_DIR/counters.env" ]]; then
    cat > "$STATE_DIR/counters.env" <<'COUNTERS'
TOTAL_DETECTIONS=0
TOTAL_BLOCKS=0
TOTAL_UNBLOCKS=0
LAST_DETECTION_TS=none
COUNTERS
  fi
}

load_counters() {
  # shellcheck source=/dev/null
  source "$STATE_DIR/counters.env"
}

save_counters() {
  cat > "$STATE_DIR/counters.env" <<COUNTERS
TOTAL_DETECTIONS=${TOTAL_DETECTIONS}
TOTAL_BLOCKS=${TOTAL_BLOCKS}
TOTAL_UNBLOCKS=${TOTAL_UNBLOCKS}
LAST_DETECTION_TS=${LAST_DETECTION_TS}
COUNTERS
}

is_whitelisted() {
  local ip="$1"
  local list=","${WHITELISTED_IPS}","
  [[ "$list" == *",$ip,"* ]]
}

is_valid_ipv4() {
  local ip="$1"
  [[ "$ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
  IFS='.' read -r -a octets <<< "$ip"
  local octet
  for octet in "${octets[@]}"; do
    (( octet >= 0 && octet <= 255 )) || return 1
  done
}

ensure_iptables() {
  if ! command -v iptables >/dev/null 2>&1; then
    echo "iptables is required but not found in PATH."
    exit 1
  fi
}

block_ip() {
  local ip="$1"
  local reason="${2:-manual}"

  is_valid_ipv4 "$ip" || { echo "Invalid IPv4 address: $ip"; exit 1; }
  is_whitelisted "$ip" && { echo "Refusing to block whitelisted IP: $ip"; exit 1; }

  ensure_iptables
  if ! iptables -C INPUT -s "$ip" -j DROP >/dev/null 2>&1; then
    iptables -A INPUT -s "$ip" -j DROP
  fi

  if ! grep -qE "^${ip}\|" "$STATE_DIR/blocked_ips.txt"; then
    printf '%s|%s|%s\n' "$ip" "$reason" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$STATE_DIR/blocked_ips.txt"
    TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))
    save_counters
  fi

  echo "Blocked $ip (reason: $reason)"
}

unblock_ip() {
  local ip="$1"
  is_valid_ipv4 "$ip" || { echo "Invalid IPv4 address: $ip"; exit 1; }

  ensure_iptables
  if iptables -C INPUT -s "$ip" -j DROP >/dev/null 2>&1; then
    iptables -D INPUT -s "$ip" -j DROP
  fi

  if grep -qE "^${ip}\|" "$STATE_DIR/blocked_ips.txt"; then
    grep -vE "^${ip}\|" "$STATE_DIR/blocked_ips.txt" > "$STATE_DIR/blocked_ips.txt.tmp" || true
    mv "$STATE_DIR/blocked_ips.txt.tmp" "$STATE_DIR/blocked_ips.txt"
    TOTAL_UNBLOCKS=$((TOTAL_UNBLOCKS + 1))
    save_counters
  fi

  echo "Unblocked $ip"
}

print_status() {
  load_counters
  local active_blocks=0
  local active_detections=0

  [[ -s "$STATE_DIR/blocked_ips.txt" ]] && active_blocks=$(wc -l < "$STATE_DIR/blocked_ips.txt")
  [[ -s "$STATE_DIR/detections.log" ]] && active_detections=$(tail -n 50 "$STATE_DIR/detections.log" | wc -l)

  echo "AntiDDoS status"
  echo "  Interface: $INTERFACE"
  echo "  Poll interval: ${POLL_INTERVAL}s"
  echo "  Active blocks: $active_blocks"
  echo "  Recent detections (last 50): $active_detections"
  echo "  Total detections: $TOTAL_DETECTIONS"
  echo "  Total blocks: $TOTAL_BLOCKS"
  echo "  Total unblocks: $TOTAL_UNBLOCKS"
  echo "  Last detection: $LAST_DETECTION_TS"

  if [[ -s "$STATE_DIR/blocked_ips.txt" ]]; then
    echo
    echo "Blocked IPs:"
    cat "$STATE_DIR/blocked_ips.txt"
  fi
}

validate_config() {
  load_config

  local errors=0
  if [[ ! "$POLL_INTERVAL" =~ ^[0-9]+$ ]] || (( POLL_INTERVAL < 1 )); then
    echo "Invalid POLL_INTERVAL: $POLL_INTERVAL"
    errors=$((errors + 1))
  fi

  if [[ ! "$RX_THRESHOLD_BYTES" =~ ^[0-9]+$ ]] || (( RX_THRESHOLD_BYTES < 1 )); then
    echo "Invalid RX_THRESHOLD_BYTES: $RX_THRESHOLD_BYTES"
    errors=$((errors + 1))
  fi

  if [[ ! "$CONNECTION_THRESHOLD" =~ ^[0-9]+$ ]] || (( CONNECTION_THRESHOLD < 1 )); then
    echo "Invalid CONNECTION_THRESHOLD: $CONNECTION_THRESHOLD"
    errors=$((errors + 1))
  fi

  if [[ ! -d "/sys/class/net/$INTERFACE" ]]; then
    echo "Network interface does not exist: $INTERFACE"
    errors=$((errors + 1))
  fi

  if [[ -n "$WHITELISTED_IPS" ]]; then
    IFS=',' read -r -a wl <<< "$WHITELISTED_IPS"
    local ip
    for ip in "${wl[@]}"; do
      is_valid_ipv4 "$ip" || { echo "Invalid WHITELISTED_IPS entry: $ip"; errors=$((errors + 1)); }
    done
  fi

  if (( errors > 0 )); then
    echo "Config validation failed with $errors error(s)."
    exit 1
  fi

  echo "Config validation passed: $CONFIG_FILE"
}

get_top_source_ip() {
  local ports_expr=""
  local port
  IFS=',' read -r -a ports <<< "$MONITORED_PORTS"
  for port in "${ports[@]}"; do
    [[ -n "$ports_expr" ]] && ports_expr+=" or "
    ports_expr+="sport = :$port"
  done

  ss -H -tn state established "($ports_expr)" 2>/dev/null \
    | awk '{split($5,a,":"); print a[1]}' \
    | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort | uniq -c | sort -nr | awk 'NR==1{print $2" "$1}'
}

run_start() {
  validate_config
  load_config
  state_init
  load_counters

  ensure_iptables

  echo "Starting AntiDDoS monitor loop (Ctrl+C to stop)"
  echo "Interface=$INTERFACE interval=${POLL_INTERVAL}s rx_threshold=${RX_THRESHOLD_BYTES} connection_threshold=${CONNECTION_THRESHOLD}"

  local prev_rx curr_rx delta_rx now top_ip top_count
  prev_rx=$(cat "/sys/class/net/$INTERFACE/statistics/rx_bytes")

  while true; do
    sleep "$POLL_INTERVAL"
    curr_rx=$(cat "/sys/class/net/$INTERFACE/statistics/rx_bytes")
    delta_rx=$((curr_rx - prev_rx))
    prev_rx="$curr_rx"

    read -r top_ip top_count <<< "$(get_top_source_ip || true)"
    top_ip="${top_ip:-}"
    top_count="${top_count:-0}"

    if (( delta_rx > RX_THRESHOLD_BYTES )) || (( top_count > CONNECTION_THRESHOLD )); then
      now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      TOTAL_DETECTIONS=$((TOTAL_DETECTIONS + 1))
      LAST_DETECTION_TS="$now"
      printf '%s|delta_rx=%s|top_ip=%s|top_conn=%s\n' "$now" "$delta_rx" "${top_ip:-none}" "$top_count" >> "$STATE_DIR/detections.log"
      save_counters

      if [[ -n "$top_ip" ]] && ! is_whitelisted "$top_ip"; then
        block_ip "$top_ip" "auto-detect"
      fi
    fi
  done
}

run_simulate() {
  load_config
  state_init
  load_counters

  local log_file="${1:-$SIMULATE_LOG}"
  if [[ -z "$log_file" ]]; then
    echo "Usage: $0 simulate <logfile>"
    echo "Or set SIMULATE_LOG in config."
    exit 1
  fi

  if [[ ! -f "$log_file" ]]; then
    echo "Simulation log not found: $log_file"
    exit 1
  fi

  echo "Replaying log: $log_file"
  local ts ip conn pps
  while read -r ts ip conn pps; do
    [[ -z "$ts" || "$ts" =~ ^# ]] && continue
    if (( conn > CONNECTION_THRESHOLD || pps > RX_THRESHOLD_BYTES )); then
      TOTAL_DETECTIONS=$((TOTAL_DETECTIONS + 1))
      LAST_DETECTION_TS="$ts"
      printf '%s|simulated|ip=%s|conn=%s|pps=%s\n' "$ts" "$ip" "$conn" "$pps" >> "$STATE_DIR/detections.log"
      if ! is_whitelisted "$ip"; then
        if is_valid_ipv4 "$ip"; then
          printf '%s|%s|%s\n' "$ip" "simulate" "$ts" >> "$STATE_DIR/blocked_ips.txt"
          TOTAL_BLOCKS=$((TOTAL_BLOCKS + 1))
        fi
      fi
    fi
  done < "$log_file"

  save_counters
  echo "Simulation complete."
}

usage() {
  cat <<USAGE
Usage: $0 <command> [args]

Commands:
  start                     Start monitor + detect + mitigate loop
  status                    Show live counters, active detections, and active blocks
  block <ip> [reason]       Manually block an IP
  unblock <ip>              Remove block for an IP
  config validate           Validate configuration file
  simulate [logfile]        Replay test traffic logs
USAGE
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    start)
      shift
      run_start "$@"
      ;;
    status)
      load_config
      state_init
      print_status
      ;;
    block)
      shift
      load_config
      state_init
      load_counters
      [[ $# -ge 1 ]] || { echo "Usage: $0 block <ip> [reason]"; exit 1; }
      block_ip "$1" "${2:-manual}"
      ;;
    unblock)
      shift
      load_config
      state_init
      load_counters
      [[ $# -eq 1 ]] || { echo "Usage: $0 unblock <ip>"; exit 1; }
      unblock_ip "$1"
      ;;
    config)
      shift
      case "${1:-}" in
        validate) validate_config ;;
        *) usage; exit 1 ;;
      esac
      ;;
    simulate)
      shift
      run_simulate "$@"
      ;;
    -h|--help|help|"")
      usage
      ;;
    *)
      echo "Unknown command: $cmd"
      usage
      exit 1
      ;;
  esac
}

main "$@"
