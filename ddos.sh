#tested and coded by ovhgermany @bots.syn
#also you can edit how you would like just dont steal credits pls

#!/bin/bash

# Set the maximum number of connections per IP
MAX_CONNECTIONS=100

# Set the number of seconds to wait before resetting the connection count for an IP
RESET_TIME=300

# Set the IP address of the user to whitelist
WHITELISTED_IP=128.0.0.1

# Flush existing iptables rules
iptables -F

# Allow established connections
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow traffic to the loopback interface
iptables -A INPUT -i lo -j ACCEPT

# Allow traffic from the whitelisted IP
iptables -A INPUT -s $WHITELISTED_IP -j ACCEPT

# Block SYN and ACK requests from all other IPs
iptables -A INPUT -p tcp ! --syn -m conntrack --ctstate NEW -j DROP
iptables -A INPUT -p tcp --tcp-flags FIN,ACK,PSH,SYN,URG NONE -j DROP
iptables -A INPUT -p tcp --tcp-flags FIN,ACK FIN,ACK -j DROP
iptables -A INPUT -p tcp --tcp-flags FIN,ACK,URG FIN -j DROP
iptables -A INPUT -p tcp --tcp-flags FIN,ACK,URG FIN,ACK,URG -j DROP

# Block traffic that exceeds the maximum number of connections per IP
iptables -A INPUT -p tcp -m connlimit --connlimit-above $MAX_CONNECTIONS -j DROP

# Reset the connection count for an IP after a certain amount of time has passed
iptables -A INPUT -p tcp -m recent --name conn_limit --rcheck --seconds $RESET_TIME -j ACCEPT
iptables -A INPUT -p tcp -m recent --name conn_limit --set -j DROP

# Allow all other traffic
iptables -A INPUT -j ACCEPT

# Save the iptables rules
/sbin/service iptables save
