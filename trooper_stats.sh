#!/bin/bash

# =========================================================================
# FIRST SOLDIER (ID 0) UPGRADE & STATS SCRIPT (trooper_stats.sh)
# =========================================================================

function authenticate {
    # If cookies.txt exists in the folder, seed the cookie jar with it
    if [[ -f "$prefix/cookies.txt" ]]; then
        cp "$prefix/cookies.txt" "$cookie_file"
    fi

    # 1. Hit the root/hq page first to initialize session
    $curl "$site/" > /dev/null

    # 2. Authenticate via POST /login
    if [[ -n "$password" ]]; then
        $curl --referer "$site/" \
            --data-urlencode "login=$login_lower" \
            --data-urlencode "pass=$password" \
            "$site/login" > /dev/null
    else
        $curl --referer "$site/" \
            --data-urlencode "login=$login_lower" \
            "$site/login" > /dev/null
    fi
}

function cleanup {
    [[ -n "$cookie_file" && -f "$cookie_file" ]] && rm --force "$cookie_file"
}

trap "cleanup" EXIT

### VARIABLES ###
prefix="$(dirname "$0")"
ext="com"

[[ -f "$prefix/troopers.cfg" ]] && source "$prefix/troopers.cfg"
[[ -f "$prefix/$ext.culture" ]] && source "$prefix/$ext.culture"

if [[ -z "$1" ]]; then
    echo "Usage: $0 <login> [password] [upgrade_log_file]"
    exit 1
fi

login_original="$1"
password="${2:-$password}"
upgrade_log="$3"
login_lower=$(echo "$login_original" | tr '[:upper:]' '[:lower:]')

site="https://$login_lower.trooperstest.gued.es"
cookie_file="$(mktemp -t "$login_lower.XXXXXX" --suffix='.cookie' 2>/dev/null || mktemp)"
curl="curl -L --silent -A Mozilla/5.0 --cookie $cookie_file --cookie-jar $cookie_file"

# 1. Authenticate into the account
authenticate

echo "========================================="
echo "  FIRST SOLDIER (ID 0) STATS: $login_original"
echo "========================================="

# 2. Fetch ONLY the first soldier page (ID 0) and strip carriage returns (\r)
id=0
t_html=$($curl "$site/t/$id" | tr -d '\r')

# Extract standalone numbers for Money (nums[0]) and Army Power (nums[1])
mapfile -t nums < <(echo "$t_html" | sed -n 's/^[[:space:]]*\([0-9]\{1,6\}\)[[:space:]]*$/\1/p')

if [[ ${#nums[@]} -lt 1 ]]; then
    echo "Could not retrieve Soldier #1 (ID 0) data for $login_original (check login/password)."
    echo "========================================="
    exit 1
fi

money="${nums[0]}"
army_power="${nums[1]:-0}"

# Parse the exact "Upgrade for <COST>" text from <td class="sheetright">
t_cost=$(echo "$t_html" | grep -Eoi 'Upgrade for [0-9]+' | grep -Eo '[0-9]+' | head -n 1)

# Fallback if third standalone number is present and "Upgrade for" wasn't matched
if [[ -z "$t_cost" && -n "${nums[2]:-}" ]]; then
    t_cost="${nums[2]}"
fi

# Extract Soldier Name (from rename input or page title)
t_name=$(echo "$t_html" | sed -n 's/.*id="name" name="name" type="text" value="\([^"]*\)".*/\1/p' | head -n 1)
if [[ -z "$t_name" ]]; then
    t_name=$(echo "$t_html" | sed -n "s/.*<title>MiniTroopers - \(.*\)&#39;s stats sheet<\/title>.*/\1/p" | head -n 1)
fi
[[ -z "$t_name" ]] && t_name="Soldier #1"

echo "Current Gold : $money | Army Power : $army_power"
echo "-----------------------------------------"

# Check if we got a valid numeric upgrade cost for Soldier ID 0
if [[ -n "$t_cost" && "$t_cost" =~ ^[0-9]+$ ]]; then
    if [[ "$money" -ge "$t_cost" ]]; then
        status="[UPGRADABLE!]"
        printf "  #1 (ID 0) %-14s | Next Upgrade: %-4d gold | %s\n" "($t_name)" "$t_cost" "$status"
        echo "-----------------------------------------"
        echo "Status : READY TO UPGRADE FIRST SOLDIER!"

        # Log this account if an upgrade log file path was provided
        if [[ -n "$upgrade_log" ]]; then
            printf "%-15s | Gold: %-4s | Upgrade Cost: %-4s | Soldier #1 (ID 0): %s\n" \
                "$login_original" "$money" "$t_cost" "$t_name" >> "$upgrade_log"
        fi
    else
        needed=$((t_cost - money))
        status="(Needs $needed more gold)"
        printf "  #1 (ID 0) %-14s | Next Upgrade: %-4d gold | %s\n" "($t_name)" "$t_cost" "$status"
        echo "-----------------------------------------"
        echo "Status : Need $needed more gold to upgrade Soldier #1."
    fi
else
    printf "  #1 (ID 0) %-14s | Next Upgrade: [Hidden - Army requires password/owner cookie]\n" "($t_name)"
    echo "-----------------------------------------"
    echo "Status : Could not see 'Upgrade for X' button (check password or cookies.txt)."
fi
echo "========================================="