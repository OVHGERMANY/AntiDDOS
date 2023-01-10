#!/bin/bash

# Display a banner with the script name and version
echo "OVHGERMANY Anti-DDoS Script"
echo "Version 1.0"
echo

# Install fail2ban
echo "Installing fail2ban..."
sudo apt-get install fail2ban

# Create a configuration file for fail2ban
echo "Creating a configuration file for fail2ban..."
sudo touch /etc/fail2ban/my-jail.local

# Add the following lines to define the settings for your jail
echo "Configuring fail2ban settings..."
cat <<EOT >> /etc/fail2ban/my-jail.local
[my-jail]
enabled = true
filter = my-filter
logpath = /root
maxretry = 5
findtime = 600
bantime = 600
EOT

# Create a filter file for fail2ban
echo "Creating a filter file for fail2ban..."
sudo touch /etc/fail2ban/filter.d/my-filter.conf

# Add the following lines to define the rules for matching malicious activity
echo "Configuring filter rules for fail2ban..."
cat <<EOT >> /etc/fail2ban/filter.d/my-filter.conf
[Definition]
failregex = <HOST>.*Invalid password for user
            <HOST>.*Failed password for user
ignoreregex =
EOT

# Restart fail2ban
echo "Restarting fail2ban..."
sudo service fail2ban restart

# Display a completion message
echo
echo -e "\033[32mCompleted. Move on to the next step.\033[0m"


#!/bin/bash

# Display a banner with the script name and version
echo "OVHGERMANY Anti-DDoS Script"
echo "Version 0.9b"
echo

# Install fail2ban
echo "Installing fail2ban..."
sudo apt-get install fail2ban

# Create a configuration file for fail2ban
echo "Creating a configuration file for fail2ban..."
sudo touch /etc/fail2ban/my-jail.local

# Add the following lines to define the settings for your jail
echo "Configuring fail2ban settings..."
cat <<EOT >> /etc/fail2ban/my-jail.local
[my-jail]
enabled = true
filter = my-filter
logpath = /var/log/auth.log
maxretry = 5
findtime = 600
bantime = 600
EOT

# Create a filter file for fail2ban
echo "Creating a filter file for fail2ban..."
sudo touch /etc/fail2ban/filter.d/my-filter.conf

# Add the following lines to define the rules for matching malicious activity
echo "Configuring filter rules for fail2ban..."
cat <<EOT >> /etc/fail2ban/filter.d/my-filter.conf
[Definition]
failregex = <HOST>.*Invalid password for user
            <HOST>.*Failed password for user
            <HOST>.*session opened for user
ignoreregex =
EOT

# Restart fail2ban
echo "Restarting fail2ban..."
sudo service fail2ban restart

# Display a completion message
echo
echo -e "\033[32mCompleted. Move on to the next step.\033[0m"
