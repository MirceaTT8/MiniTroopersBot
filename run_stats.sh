#!/bin/bash

# Define accounts with passwords here ("username:password")

prefix="$(dirname "$0")"
if [[ -f "$prefix/secret.cfg" ]]; then
    source "$prefix/secret.cfg"
else
    echo "Error: secret.cfg not found in $prefix"
    exit 1
fi

UPGRADE_LOG="upgradeable_accounts.log"
> "$UPGRADE_LOG" # Clear the log file before starting

for entry in "${accounts[@]}"; do
    # Split the string at the colon to get the username and password
    username="${entry%%:*}"
    password="${entry#*:}"
    
    echo "------------------------------------------------"
    echo "Checking stats for account: $username with password : $password"
    
    # Run the stats script and pass the log file as the 3rd argument
    ./trooper_stats.sh "$username" "$password" "$UPGRADE_LOG"
    
    # 2-second delay between accounts to prevent server blocks
    sleep 2
done

for i in {1..7}; do
    echo "=== Checking stats for berbelita$i ==="
    ./trooper_stats.sh "berbelita$i" "" "$UPGRADE_LOG"
    sleep 2
done

for i in {1..4}; do
    echo "=== Checking stats for otniel$i ==="
    ./trooper_stats.sh "otniel$i" "" "$UPGRADE_LOG"
    sleep 2
done

for i in {1..4}; do
    echo "=== Checking stats for marian$i ==="
    ./trooper_stats.sh "marian$i" "" "$UPGRADE_LOG"
    sleep 2
done

for i in {1..4}; do
    echo "=== Checking stats for belgin$i ==="
    ./trooper_stats.sh "belgin$i" "" "$UPGRADE_LOG"
    sleep 2
done


echo "------------------------------------------------"
echo "All account statistics processed successfully!"
echo ""
echo "========================================================================="
echo "        ACCOUNTS WHERE SOLDIER #1 (ID 0) CAN BE UPGRADED                 "
echo "========================================================================="
if [[ -s "$UPGRADE_LOG" ]]; then
    cat "$UPGRADE_LOG"
else
    echo "No accounts currently have enough gold to upgrade Soldier #1 (ID 0)."
fi
echo "========================================================================="