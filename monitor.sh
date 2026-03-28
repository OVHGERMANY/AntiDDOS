#!/bin/bash

set -u

INTERFACE=""
INTERVAL=1
JSON_STDOUT=0
TOP_N=5
WINDOW_SIZE=10
LOG_FILE="/var/log/antiddos/events.log"
LOG_FALLBACK="./events.log"
USE_IPTABLES=0
IPTABLES_CHAIN="ANTIDDOS_MONITOR"

TCP_PKTS=0; TCP_BYTES=0
UDP_PKTS=0; UDP_BYTES=0
ICMP_PKTS=0; ICMP_BYTES=0
SYN_PKTS=0

declare -a WINDOW_TOTAL_BPS=()
declare -a WINDOW_TOTAL_PPS=()
declare -a WINDOW_SYN_PPS=()

usage() {
  cat <<USAGE
Usage: $0 [--interface IFACE] [--interval SECONDS] [--json] [--top N]

Options:
  --interface, -i   Network interface to monitor (default: primary route interface)
  --interval,  -t   Sample interval in seconds (default: 1)
  --json            Print JSON to stdout instead of dashboard
  --top             Number of top source IPs to display (default: 5)
  --help, -h        Show this help
USAGE
}

err() { echo "[monitor] $*" >&2; }

have_cmd() { command -v "$1" >/dev/null 2>&1; }

json_escape() {
  echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

resolve_interface() {
  if [[ -n "$INTERFACE" ]]; then
    return 0
  fi

  INTERFACE=$(ip route 2>/dev/null | awk '/default/ {for (i=1;i<=NF;i++) if ($i=="dev") {print $(i+1); exit}}')
  if [[ -z "$INTERFACE" ]]; then
    INTERFACE="eth0"
  fi
}

validate_interface() {
  if [[ ! -d "/sys/class/net/$INTERFACE" ]]; then
    err "Interface '$INTERFACE' not found."
    exit 1
  fi
}

setup_logfile() {
  local dir
  dir=$(dirname "$LOG_FILE")
  if mkdir -p "$dir" 2>/dev/null && touch "$LOG_FILE" 2>/dev/null; then
    return 0
  fi

  err "Cannot write to $LOG_FILE, falling back to $LOG_FALLBACK"
  LOG_FILE="$LOG_FALLBACK"
  touch "$LOG_FILE" 2>/dev/null || {
    err "Cannot write fallback log file '$LOG_FILE'."
    exit 1
  }
}

setup_iptables_counters() {
  have_cmd iptables || return 1

  iptables -t raw -N "$IPTABLES_CHAIN" >/dev/null 2>&1 || true
  iptables -t raw -F "$IPTABLES_CHAIN" >/dev/null 2>&1 || return 1

  iptables -t raw -C PREROUTING -i "$INTERFACE" -j "$IPTABLES_CHAIN" >/dev/null 2>&1 || \
    iptables -t raw -I PREROUTING 1 -i "$INTERFACE" -j "$IPTABLES_CHAIN" >/dev/null 2>&1 || return 1

  iptables -t raw -A "$IPTABLES_CHAIN" -p tcp -m tcp --tcp-flags FIN,SYN,RST,ACK SYN -m comment --comment ANTIDDOS_SYN -j RETURN >/dev/null 2>&1 || return 1
  iptables -t raw -A "$IPTABLES_CHAIN" -p tcp -m comment --comment ANTIDDOS_TCP -j RETURN >/dev/null 2>&1 || return 1
  iptables -t raw -A "$IPTABLES_CHAIN" -p udp -m comment --comment ANTIDDOS_UDP -j RETURN >/dev/null 2>&1 || return 1
  iptables -t raw -A "$IPTABLES_CHAIN" -p icmp -m comment --comment ANTIDDOS_ICMP -j RETURN >/dev/null 2>&1 || return 1

  USE_IPTABLES=1
  return 0
}

cleanup_iptables() {
  if [[ "$USE_IPTABLES" -eq 1 ]]; then
    iptables -t raw -D PREROUTING -i "$INTERFACE" -j "$IPTABLES_CHAIN" >/dev/null 2>&1 || true
    iptables -t raw -F "$IPTABLES_CHAIN" >/dev/null 2>&1 || true
    iptables -t raw -X "$IPTABLES_CHAIN" >/dev/null 2>&1 || true
  fi
}

read_iptables_metric() {
  local tag="$1"
  iptables-save -t raw -c 2>/dev/null | awk -v tag="$tag" '
    $0 ~ "-A ANTIDDOS_MONITOR" && $0 ~ tag {
      if (match($1, /\[([0-9]+):([0-9]+)\]/, a)) {
        print a[1], a[2]
        exit
      }
    }
  '
}

collect_protocol_counters() {
  local out
  if [[ "$USE_IPTABLES" -eq 1 ]]; then
    out=$(read_iptables_metric "ANTIDDOS_TCP"); TCP_PKTS=$(awk '{print $1+0}' <<<"$out"); TCP_BYTES=$(awk '{print $2+0}' <<<"$out")
    out=$(read_iptables_metric "ANTIDDOS_UDP"); UDP_PKTS=$(awk '{print $1+0}' <<<"$out"); UDP_BYTES=$(awk '{print $2+0}' <<<"$out")
    out=$(read_iptables_metric "ANTIDDOS_ICMP"); ICMP_PKTS=$(awk '{print $1+0}' <<<"$out"); ICMP_BYTES=$(awk '{print $2+0}' <<<"$out")
    out=$(read_iptables_metric "ANTIDDOS_SYN"); SYN_PKTS=$(awk '{print $1+0}' <<<"$out")
    return 0
  fi

  # Fallback: conntrack snapshot (requires conntrack accounting)
  if have_cmd conntrack; then
    local snapshot
    snapshot=$(conntrack -L -o extended 2>/dev/null)
    TCP_PKTS=$(awk '/^tcp/ {for (i=1;i<=NF;i++) if ($i ~ /^packets=/) {split($i,a,"="); p+=a[2]}} END {print p+0}' <<<"$snapshot")
    TCP_BYTES=$(awk '/^tcp/ {for (i=1;i<=NF;i++) if ($i ~ /^bytes=/) {split($i,a,"="); b+=a[2]}} END {print b+0}' <<<"$snapshot")
    UDP_PKTS=$(awk '/^udp/ {for (i=1;i<=NF;i++) if ($i ~ /^packets=/) {split($i,a,"="); p+=a[2]}} END {print p+0}' <<<"$snapshot")
    UDP_BYTES=$(awk '/^udp/ {for (i=1;i<=NF;i++) if ($i ~ /^bytes=/) {split($i,a,"="); b+=a[2]}} END {print b+0}' <<<"$snapshot")
    ICMP_PKTS=$(awk '/^icmp/ {for (i=1;i<=NF;i++) if ($i ~ /^packets=/) {split($i,a,"="); p+=a[2]}} END {print p+0}' <<<"$snapshot")
    ICMP_BYTES=$(awk '/^icmp/ {for (i=1;i<=NF;i++) if ($i ~ /^bytes=/) {split($i,a,"="); b+=a[2]}} END {print b+0}' <<<"$snapshot")
  else
    TCP_PKTS=0; TCP_BYTES=0
    UDP_PKTS=0; UDP_BYTES=0
    ICMP_PKTS=0; ICMP_BYTES=0
  fi

  # Fallback SYN approximation from /proc/net/snmp (active+passive opens)
  SYN_PKTS=$(awk '
    /^Tcp:/ {line++; if (line==1) {
      for (i=1;i<=NF;i++) idx[$i]=i
    } else {
      active=$(idx["ActiveOpens"] ? $(idx["ActiveOpens"]) : 0)
      passive=$(idx["PassiveOpens"] ? $(idx["PassiveOpens"]) : 0)
      print active+passive
      exit
    }}
  ' /proc/net/snmp 2>/dev/null)
  SYN_PKTS=${SYN_PKTS:-0}
}

collect_interface_totals() {
  awk -v iface="$INTERFACE" '$1 ~ iface":" {gsub(":", "", $1); print $2+0, $3+0, $10+0, $11+0; exit}' /proc/net/dev
}

collect_top_ips() {
  if have_cmd conntrack; then
    conntrack -L 2>/dev/null | awk '
      {
        for (i=1;i<=NF;i++) {
          if ($i ~ /^src=/) {
            split($i,a,"=")
            ip=a[2]
            if (ip !~ /^127\./ && ip !~ /^0\./) {
              c[ip]++
            }
            break
          }
        }
      }
      END {
        for (ip in c) {
          printf "%s %d\n", ip, c[ip]
        }
      }
    ' | sort -k2,2nr | head -n "$TOP_N"
  fi
}

window_push() {
  local -n arr=$1
  arr+=("$2")
  if (( ${#arr[@]} > WINDOW_SIZE )); then
    arr=("${arr[@]:1}")
  fi
}

window_avg() {
  local -n arr=$1
  local sum=0 v
  for v in "${arr[@]}"; do
    sum=$((sum + v))
  done
  if (( ${#arr[@]} == 0 )); then
    echo 0
  else
    echo $((sum / ${#arr[@]}))
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -i|--interface)
        INTERFACE="$2"; shift 2 ;;
      -t|--interval)
        INTERVAL="$2"; shift 2 ;;
      --json)
        JSON_STDOUT=1; shift ;;
      --top)
        TOP_N="$2"; shift 2 ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        err "Unknown argument: $1"
        usage
        exit 1 ;;
    esac
  done

  [[ "$INTERVAL" =~ ^[0-9]+([.][0-9]+)?$ ]] || { err "--interval must be a number"; exit 1; }
  [[ "$TOP_N" =~ ^[0-9]+$ ]] || { err "--top must be a positive integer"; exit 1; }
}

parse_args "$@"
resolve_interface
validate_interface
setup_logfile

if ! setup_iptables_counters; then
  err "iptables counters unavailable; using conntrack/proc fallback."
fi

trap 'cleanup_iptables; exit 0' INT TERM EXIT

prev_if_stats=$(collect_interface_totals)
prev_tcp_p=0; prev_tcp_b=0
prev_udp_p=0; prev_udp_b=0
prev_icmp_p=0; prev_icmp_b=0
prev_syn=0

collect_protocol_counters
prev_tcp_p=$TCP_PKTS; prev_tcp_b=$TCP_BYTES
prev_udp_p=$UDP_PKTS; prev_udp_b=$UDP_BYTES
prev_icmp_p=$ICMP_PKTS; prev_icmp_b=$ICMP_BYTES
prev_syn=$SYN_PKTS

while true; do
  sleep "$INTERVAL"

  now_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  curr_if_stats=$(collect_interface_totals)
  read -r prev_rx_b prev_rx_p prev_tx_b prev_tx_p <<< "$prev_if_stats"
  read -r curr_rx_b curr_rx_p curr_tx_b curr_tx_p <<< "$curr_if_stats"

  if_rx_bps=$(awk -v c="$curr_rx_b" -v p="$prev_rx_b" -v i="$INTERVAL" 'BEGIN {printf "%.0f", (c-p)/i}')
  if_tx_bps=$(awk -v c="$curr_tx_b" -v p="$prev_tx_b" -v i="$INTERVAL" 'BEGIN {printf "%.0f", (c-p)/i}')
  if_rx_pps=$(awk -v c="$curr_rx_p" -v p="$prev_rx_p" -v i="$INTERVAL" 'BEGIN {printf "%.0f", (c-p)/i}')
  if_tx_pps=$(awk -v c="$curr_tx_p" -v p="$prev_tx_p" -v i="$INTERVAL" 'BEGIN {printf "%.0f", (c-p)/i}')

  collect_protocol_counters

  tcp_pps=$(awk -v c="$TCP_PKTS" -v p="$prev_tcp_p" -v i="$INTERVAL" 'BEGIN {printf "%.0f", (c-p)/i}')
  tcp_bps=$(awk -v c="$TCP_BYTES" -v p="$prev_tcp_b" -v i="$INTERVAL" 'BEGIN {printf "%.0f", (c-p)/i}')
  udp_pps=$(awk -v c="$UDP_PKTS" -v p="$prev_udp_p" -v i="$INTERVAL" 'BEGIN {printf "%.0f", (c-p)/i}')
  udp_bps=$(awk -v c="$UDP_BYTES" -v p="$prev_udp_b" -v i="$INTERVAL" 'BEGIN {printf "%.0f", (c-p)/i}')
  icmp_pps=$(awk -v c="$ICMP_PKTS" -v p="$prev_icmp_p" -v i="$INTERVAL" 'BEGIN {printf "%.0f", (c-p)/i}')
  icmp_bps=$(awk -v c="$ICMP_BYTES" -v p="$prev_icmp_b" -v i="$INTERVAL" 'BEGIN {printf "%.0f", (c-p)/i}')
  syn_rate=$(awk -v c="$SYN_PKTS" -v p="$prev_syn" -v i="$INTERVAL" 'BEGIN {printf "%.0f", (c-p)/i}')

  total_pps=$((tcp_pps + udp_pps + icmp_pps))
  total_bps=$((tcp_bps + udp_bps + icmp_bps))

  window_push WINDOW_TOTAL_PPS "$total_pps"
  window_push WINDOW_TOTAL_BPS "$total_bps"
  window_push WINDOW_SYN_PPS "$syn_rate"

  avg_pps=$(window_avg WINDOW_TOTAL_PPS)
  avg_bps=$(window_avg WINDOW_TOTAL_BPS)
  avg_syn=$(window_avg WINDOW_SYN_PPS)

  burst_pps="no"
  burst_syn="no"
  if (( avg_pps > 0 && total_pps > avg_pps * 2 )); then burst_pps="yes"; fi
  if (( avg_syn > 0 && syn_rate > avg_syn * 2 )); then burst_syn="yes"; fi

  top_ips=$(collect_top_ips)
  top_json="[]"
  if [[ -n "$top_ips" ]]; then
    top_json=$(awk '
      BEGIN {printf "["; first=1}
      {
        if (!first) printf ",";
        printf "{\"ip\":\"%s\",\"count\":%s}", $1, $2;
        first=0;
      }
      END {printf "]"}
    ' <<< "$top_ips")
  fi

  json_line=$(cat <<JSON
{"timestamp":"$now_ts","interface":"$INTERFACE","interval":$INTERVAL,"protocol":{"tcp":{"pps":$tcp_pps,"bps":$tcp_bps},"udp":{"pps":$udp_pps,"bps":$udp_bps},"icmp":{"pps":$icmp_pps,"bps":$icmp_bps}},"syn_rate":$syn_rate,"interface_total":{"rx_bps":$if_rx_bps,"tx_bps":$if_tx_bps,"rx_pps":$if_rx_pps,"tx_pps":$if_tx_pps},"trend":{"avg_pps":$avg_pps,"avg_bps":$avg_bps,"avg_syn":$avg_syn,"burst_pps":"$burst_pps","burst_syn":"$burst_syn"},"top_sources":$top_json}
JSON
)

  echo "$json_line" >> "$LOG_FILE"

  if [[ "$JSON_STDOUT" -eq 1 ]]; then
    echo "$json_line"
  else
    clear
    echo "AntiDDOS Monitor"
    echo "Time (UTC): $now_ts | Interface: $INTERFACE | Interval: ${INTERVAL}s"
    echo
    printf "%-8s %12s %12s\n" "Proto" "Packets/s" "Bytes/s"
    printf "%-8s %12s %12s\n" "TCP" "$tcp_pps" "$tcp_bps"
    printf "%-8s %12s %12s\n" "UDP" "$udp_pps" "$udp_bps"
    printf "%-8s %12s %12s\n" "ICMP" "$icmp_pps" "$icmp_bps"
    echo
    echo "New TCP connections/s (SYN): $syn_rate"
    echo "Interface totals RX/TX (bytes/s): $if_rx_bps / $if_tx_bps"
    echo "Interface totals RX/TX (packets/s): $if_rx_pps / $if_tx_pps"
    echo "Trend avg pps: $avg_pps | avg syn: $avg_syn | burst pps: $burst_pps | burst syn: $burst_syn"
    echo
    echo "Top source IPs (window snapshot):"
    if [[ -n "$top_ips" ]]; then
      nl -w1 -s'. ' <<< "$top_ips"
    else
      echo "(no conntrack data available)"
    fi
    echo
    echo "JSON log: $LOG_FILE"
  fi

  prev_if_stats="$curr_if_stats"
  prev_tcp_p=$TCP_PKTS; prev_tcp_b=$TCP_BYTES
  prev_udp_p=$UDP_PKTS; prev_udp_b=$UDP_BYTES
  prev_icmp_p=$ICMP_PKTS; prev_icmp_b=$ICMP_BYTES
  prev_syn=$SYN_PKTS
done
