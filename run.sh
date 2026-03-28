#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

cat <<'MSG'
[DEPRECATED] run.sh interactive editing is no longer supported.

Please use config files and antiddos.sh subcommands instead:
  1) Copy config/antiddos.conf.example to config/antiddos.conf
  2) Edit configuration values (whitelist, thresholds, interface, state dir)
  3) Validate config: ./antiddos.sh config validate
  4) Start daemon loop: ./antiddos.sh start

Manual block controls:
  ./antiddos.sh block <ip> [reason]
  ./antiddos.sh unblock <ip>
MSG

exec "$SCRIPT_DIR/antiddos.sh" config validate
