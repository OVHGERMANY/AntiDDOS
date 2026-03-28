# AntiDDOS

A Bash-based anti-DDoS toolkit with a single entrypoint script (`antiddos.sh`) that supports monitoring, detection, mitigation, simulation, and operational status reporting.

> `run.sh` is deprecated for interactive edits. Configuration is now file-driven.

## Quick start

1. Clone/download this repository.
2. Make scripts executable:
   ```bash
   chmod +x antiddos.sh run.sh
   ```
3. Create/edit config:
   ```bash
   cp config/antiddos.conf.example config/antiddos.conf
   $EDITOR config/antiddos.conf
   ```
4. Validate:
   ```bash
   ./antiddos.sh config validate
   ```
5. Start protection loop:
   ```bash
   ./antiddos.sh start
   ```

## Main entry script

The main operational interface is:

```bash
./antiddos.sh <subcommand>
```

### Subcommands

#### `start`
Starts the monitor + detect + mitigate loop.

Detection signals include:
- RX byte delta above `RX_THRESHOLD_BYTES`
- Top source connection count above `CONNECTION_THRESHOLD`

When an event is detected, it is logged into `STATE_DIR/detections.log`; if a top IP is identified and not whitelisted, it is blocked with iptables.

#### `status`
Prints runtime status including:
- live counters (`TOTAL_DETECTIONS`, `TOTAL_BLOCKS`, `TOTAL_UNBLOCKS`)
- active detections (recent detection count)
- active blocks (`blocked_ips.txt`)

#### `block <ip> [reason]`
Manually blocks an IPv4 using iptables and records it in state.

Examples:
```bash
./antiddos.sh block 203.0.113.15
./antiddos.sh block 203.0.113.15 "manual review"
```

#### `unblock <ip>`
Removes an existing iptables block and removes the IP from state tracking.

Example:
```bash
./antiddos.sh unblock 203.0.113.15
```

#### `config validate`
Validates configuration values and interface presence.

Example:
```bash
./antiddos.sh config validate
```

#### `simulate [logfile]`
Replays a test traffic log for dry-run style detection/block simulation (without changing iptables rules).

Input format per line:

```text
<timestamp> <ip> <connections> <pps_bytes>
```

Example:
```bash
./antiddos.sh simulate tests/sample_traffic.log
```

## Configuration

Edit `config/antiddos.conf` (copy from `.example`).

All supported options:

- `INTERFACE` — network interface to monitor (default: `eth0`)
- `POLL_INTERVAL` — polling interval in seconds
- `RX_THRESHOLD_BYTES` — detection threshold for received-byte delta per poll
- `CONNECTION_THRESHOLD` — max allowed top-source established connections
- `MONITORED_PORTS` — comma-separated ports used in connection analysis (e.g. `80,443`)
- `WHITELISTED_IPS` — comma-separated IPv4 list never auto-blocked
- `STATE_DIR` — persistent state dir (`counters.env`, `detections.log`, `blocked_ips.txt`)
- `SIMULATE_LOG` — optional default log path for `simulate`

You can override config location with:

```bash
ANTIDDOS_CONFIG=/path/to/antiddos.conf ./antiddos.sh status
```

## Deprecated flow (`run.sh`)

`run.sh` no longer performs interactive script edits. It now:
- prints migration guidance to config-driven usage
- runs `./antiddos.sh config validate`

## Systemd daemon example

A sample unit file is available at:

- `examples/antiddos.service`

Install example:

```bash
sudo mkdir -p /opt/antiddos
sudo cp -r . /opt/antiddos
sudo cp /opt/antiddos/examples/antiddos.service /etc/systemd/system/antiddos.service
sudo systemctl daemon-reload
sudo systemctl enable --now antiddos.service
sudo systemctl status antiddos.service
```

## Notes

- This project relies on Linux networking tools (`ss`, `iptables`) and root privileges for blocking/unblocking.
- Validate config before starting in production.
