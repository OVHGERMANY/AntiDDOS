#!/bin/bash

# Flush existing iptables rules
iptables -F

# Set the maximum number of connections per IP
MAX_CONNECTIONS=100

# Set the number of seconds to wait before resetting the connection count for an IP
RESET_TIME=300

# Set the IP address of the user to whitelist
WHITELISTED_IP=1.1.1.1

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

# Block UDP traffic that exceeds the maximum number of packets per second
iptables -A INPUT -p udp -m limit --limit 50/second --limit-burst 100 -j ACCEPT

# Block traffic that exceeds the maximum number of connections per IP
iptables -A INPUT -p tcp -m connlimit --connlimit-above $MAX_CONNECTIONS -j DROP

# Reset the connection count for an IP after a certain amount of time has passed
iptables -A INPUT -p tcp -m recent --name conn_limit --rcheck --seconds $RESET_TIME -j ACCEPT
iptables -A INPUT -p tcp -m recent --name conn_limit --set -j DROP

# Block traffic with invalid TCP flags
iptables -A INPUT -p tcp --tcp-flags ALL ALL -j DROP
iptables -A INPUT -p tcp --tcp-flags ALL NONE -j DROP

# Block traffic with invalid IP options
iptables -A INPUT -m ipoption --ipopt-type any -j DROP

# Block traffic with invalid TCP options
iptables -A INPUT -p tcp --tcp-options ALL NONE -j DROP
iptables -A INPUT -p tcp --tcp-options SYN,RST SYN,RST -j DROP

# Block packets with spoofed IPs
iptables -A INPUT -s 10.0.0.0/8 -j DROP
iptables -A INPUT -s 172.16.0.0/12 -j DROP
iptables -A INPUT -s 192.168.0.0/16 -j DROP

# Allow all other traffic
iptables -A INPUT -j ACCEPT

# Save the iptables rules
/sbin/service iptables save
