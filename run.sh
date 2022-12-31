#!/bin/bash

# Set the filename of the DDoS protection script
DDOS_SCRIPT=ddos.sh

# Display a banner with the text "Made by OVHGERMANY" and "Version 0.7 Beta"
echo "#############################################"
echo "# Made by OVHGERMANY/@bots.syn             #"
echo "# Version 0.8 Beta                         #"
echo "#############################################"
echo

# Display a message explaining what the script does
echo "This script allows you to update the whitelist in the DDoS protection script, reset the iptables rules, or add a new IP address to the whitelist."
echo

# Display the available options
echo "What would you like to do?"
echo "  1) Reset iptables"
echo "  2) Update whitelist"
echo "  3) Add new IP to whitelist"
echo "  4) Remove IP from whitelist"
echo

# Prompt the user for their choice
read -p "Enter your choice (1-4): " CHOICE

# Process the user's choice
case $CHOICE in
  1)
    # Reset the iptables
    iptables -F
    /sbin/service iptables save
    echo "Iptables reset."
    ;;
  2)
    # Prompt the user for their IP address
    read -p "Enter your IP address: " IP_ADDRESS

    # Update the DDoS protection script with the user's IP address
    sed -i "s/WHITELISTED_IP=.*/WHITELISTED_IP=$IP_ADDRESS/" $DDOS_SCRIPT

    bash $DDOS_SCRIPT
    echo "Whitelist updated."
    ;;
  3)
    # Prompt the user for the new IP address
   
    read -p "Enter the new IP address: " NEW_IP_ADDRESS

    # Confirm the user's action
    read -p "Are you sure you want to add $NEW_IP_ADDRESS to the whitelist? (y/n) " CONFIRM

    # Process the user's confirmation
    case $CONFIRM in
      y|Y)
        # Add the new IP address to the whitelist
        sed -i "/# Set the IP address of the user to whitelist/a\WHITELISTED_IP=$NEW_IP_ADDRESS" $DDOS_SCRIPT

        # Run the DDoS protection script
        bash $DDOS_SCRIPT
        echo "$NEW_IP_ADDRESS added to whitelist."
        ;;
      n|N)
        # Do nothing
        ;;
      *)
        # Display an error message
        echo "Invalid input. Aborting."
        ;;
    esac
    ;;
  4)
    # Prompt the user for the IP address to remove
    read -p "Enter the IP address to remove: " REMOVE_IP_ADDRESS

    # Confirm the user's action
    read -p "Are you sure you want to remove $REMOVE_IP_ADDRESS from the whitelist? (y/n) " CONFIRM

    # Process the user's confirmation
    case $CONFIRM in
      y|Y)
        # Remove the IP address from the whitelist
        sed -i "/WHITELISTED_IP=$REMOVE_IP_ADDRESS/d" $DDOS_SCRIPT

        # Run the DDoS protection script
        bash $DDOS_SCRIPT
        echo "$REMOVE_IP_ADDRESS removed from whitelist."
        ;;
      n|N)
        # Do nothing
        ;;
      *)
        # Display an error message
        echo "Invalid input. Aborting."
        ;;
    esac
    ;;
  *)
    # Display an error message
    echo "Invalid choice. Aborting."
    ;;
esac
