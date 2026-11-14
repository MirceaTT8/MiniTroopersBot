#!/bin/bash

# Define your accounts in a "username:password" format.
# If an account has no password, leave it blank after the colon (e.g., "account3:").

prefix="$(dirname "$0")"
ext="com"

echo "Starting automated runs for all accounts..."

if [[ -f "$prefix/secret.cfg" ]]; then
    source "$prefix/secret.cfg"
else
    echo "Error: $prefix/secret.cfg not found!"
    exit 1
fi


# Loop through each account entrgy
for entry in "${accounts[@]}"; do
    # Split the string at the colon to get the username and password
    username="${entry%%:*}"
    password="${entry#*:}"
    
    echo "------------------------------------------------"
    echo "Executing bot for account: $username with password : $password"

    
    # Run the main bot script
    ./troopers.sh "$username" "$password"
    
    # 2-second delay between accounts to prevent server blocks
    sleep 2
done

for i in {1..7}; do echo "=== Running for berbelita$i ==="; ./troopers.sh berbelita$i; done
for i in {1..4}; do echo "=== Running for otniel$i ==="; ./troopers.sh otniel$i; done
for i in {1..4}; do echo "=== Running for marian$i ==="; ./troopers.sh marian$i; done
for i in {1..4}; do echo "=== Running for belgin$i ==="; ./troopers.sh belgin$i; done

echo "------------------------------------------------"
echo "All accounts processed successfully!"