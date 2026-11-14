#!/bin/bash

# =========================================================================
# ACCOUNT RECRUITS COUNTER SCRIPT (check_recruits.sh)
# =========================================================================

# 1. Define your accounts in "username:password" format.
#    If an account has no password, leave the part after the colon empty ("username:")


OUTPUT_FILE="account_and_recruits.txt"
prefix="$(dirname "$0")"
ext="com"

if [[ -f "$prefix/secret.cfg" ]]; then
    source "$prefix/secret.cfg"
else
    echo "Error: $prefix/secret.cfg not found!"
    exit 1
fi

[[ -f "$prefix/secret.cfg" ]] && source "$prefix/secret.cfg"
[[ -f "$prefix/$ext.culture" ]] && source "$prefix/$ext.culture"

# Initialize the output file header
{
    echo "===================================================="
    echo "           ACCOUNTS WITH RECRUITS                   "
    echo "===================================================="
    printf "%-20s | %s\n" "ACCOUNT" "RECRUITS COUNT"
    echo "----------------------------------------------------"
} > "$OUTPUT_FILE"

function check_account_recruits {
    local login_original="$1"
    local password="$2"
    local login_lower
    login_lower=$(echo "$login_original" | tr '[:upper:]' '[:lower:]')

    local site="https://$login_lower.trooperstest.gued.es"
    local cookie_file
    cookie_file="$(mktemp -t "$login_lower.XXXXXX" --suffix='.cookie' 2>/dev/null || mktemp)"
    local curl_cmd="curl -L --silent -A Mozilla/5.0 --cookie $cookie_file --cookie-jar $cookie_file"

    # Seed with cookies.txt if present
    if [[ -f "$prefix/cookies.txt" ]]; then
        cp "$prefix/cookies.txt" "$cookie_file"
    fi

    # 1. Initialize session and login
    $curl_cmd "$site/" > /dev/null
    if [[ -n "$password" ]]; then
        $curl_cmd --referer "$site/" \
            --data-urlencode "login=$login_lower" \
            --data-urlencode "pass=$password" \
            "$site/login" > /dev/null
    else
        $curl_cmd --referer "$site/" \
            --data-urlencode "login=$login_lower" \
            "$site/login" > /dev/null
    fi

    # 2. Fetch /history
    local history_html
    history_html=$($curl_cmd "$site/history")

    # 3. Flatten all newlines (\r and \n) into spaces, strip HTML tags, and squeeze spaces
    #    This turns:
    #      You have recruited \n <strong>14</strong> \n <img src="/favicon.ico"> \n troopers.
    #    into:
    #      You have recruited 14 troopers.
    local recruits_count
    recruits_count=$(
        echo "$history_html" \
        | tr '\r\n' '  ' \
        | sed 's/<[^>]*>/ /g' \
        | tr -s ' ' \
        | grep -Eoi 'You have recruited [0-9]+ troopers?' \
        | grep -Eo '[0-9]+' \
        | tail -n 1
    )

    # 4. Only save to account_and_recruits.txt if the account has recruits (> 0)
    if [[ -n "$recruits_count" && "$recruits_count" -gt 0 ]]; then
        printf "[+] %-16s : %s recruits (Saved to %s)\n" "$login_original" "$recruits_count" "$OUTPUT_FILE"
        printf "%-20s | %s\n" "$login_original" "$recruits_count" >> "$OUTPUT_FILE"
    else
        printf "[-] %-16s : No recruits (or cannot access /history) - Skipped\n" "$login_original"
    fi

    # Clean up temporary cookie file
    [[ -f "$cookie_file" ]] && rm --force "$cookie_file"
}

echo "Checking /history for ${#accounts[@]} accounts..."
echo "----------------------------------------------------"

for entry in "${accounts[@]}"; do
    username="${entry%%:*}"
    password="${entry#*:}"

    check_account_recruits "$username" "$password"

    # 2-second delay to prevent server blocks
    sleep 2
done

echo "====================================================" >> "$OUTPUT_FILE"
echo "----------------------------------------------------"
echo "Done! Accounts with recruits have been saved to: $OUTPUT_FILE"