# Discontinued

# AntiDDOS
Welcome to my project! This project is an anti-DDoS script that aims to protect websites and servers from distributed denial of service attacks. It has been developed using Bash and iptables, and is intended for use by server administrators and website owners.

The script includes features such as a whitelist for trusted IP addresses, the ability to reset iptables rules, and the ability to add and remove IP addresses from the whitelist. It also includes a traffic monitor that displays incoming and outgoing traffic in real-time, and can alert the user if the traffic exceeds a specified threshold.

I hope you find this script useful in protecting your website or server from DDoS attacks. Please don't hesitate to leave feedback or suggestions. Thank you for checking out my project!

# Install

Visit the project page on GitHub and click the "Clone or download" button.

Choose to either "Download ZIP" or clone the repository using Git. If you choose to clone the repository, open a terminal and enter the following command: git clone https://github.com/OVHGERMANY/AntiDDOS.git

To run this script, follow these steps:

1. Drag and drop all of the script files into the desired directory.
2. Run the following command to give the script files execute permission:
   chmod 777 *
3. Run the f2b.sh script:
   ./f2b.sh
4. Run the run.sh script:
   ./run.sh
5. Follow the prompts to update your IP address and configure the DDoS protection script.
6. To start the traffic monitor, run the following command:
   ./traffic_monitor.sh -i INTERFACE -t INTERVAL
   Replace "INTERFACE" with the name of the network interface you want to monitor (e.g. "eth0") and "INTERVAL" with the number of seconds between updates (e.g. "1").

Note: This script has been tested on Ubuntu 20.04, but it may not work on other operating systems or versions. It is still in development and you may encounter issues.

To configure the script, open the file in a text editor and follow the instructions in the comments.


## Advanced Monitoring Module

A new monitor script (`monitor.sh`) samples traffic every N seconds and reports:

- Packets/sec and bytes/sec by protocol (TCP, UDP, ICMP)
- New TCP connections/sec (SYN rate)
- Top source IPs over each sample snapshot
- Rolling trend/burst detection over the last 10 samples

### Usage

```bash
./monitor.sh --interface eth0 --interval 1 --top 10
```

Optional flags:

- `--json` to emit JSON to stdout (JSON lines are always written to `/var/log/antiddos/events.log`, with fallback to `./events.log` when permissions are missing).
- `--interface` to choose interface.
- `--interval` to set sample interval in seconds.
- `--top` to choose how many source IPs to display.

The script prefers iptables raw-table counters for protocol/SYN metrics and gracefully falls back to conntrack + `/proc` stats when iptables access is unavailable.

