#!/bin/bash

# =========================================================================
# SINGLE ACCOUNT UPGRADE & SOLDIER STATISTICS SCRIPT (trooper_stats.sh)
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
    echo "Usage: $0 <login> [password]"
    exit 1
fi

login_original="$1"
password="${2:-$password}"
login_lower=$(echo "$login_original" | tr '[:upper:]' '[:lower:]')

site="https://$login_lower.trooperstest.gued.es"
cookie_file="$(mktemp -t "$login_lower.XXXXXX" --suffix='.cookie' 2>/dev/null || mktemp)"
curl="curl -L --silent -A Mozilla/5.0 --cookie $cookie_file --cookie-jar $cookie_file"

# 1. Authenticate into the account
authenticate

# 2. Fetch /hq to discover all soldier IDs (/t/0, /t/1, /t/2, etc.)
hq_html=$($curl "$site/hq" | tr -d '\r')

# Extract unique soldier indices linked on the HQ page (sorted numerically)
mapfile -t troop_ids < <(echo "$hq_html" | grep -Eo 'href="/t/[0-9]+"' | grep -Eo '[0-9]+' | sort -n -u)

# Fallback: if /hq didn't list links explicitly, probe sequentially starting from 0
if [[ ${#troop_ids[@]} -eq 0 ]]; then
    troop_ids=(0 1 2 3 4 5 6 7 8 9 10 11)
    probe_mode=1
else
    probe_mode=0
fi

money=""
army_power=""
total_soldiers=0
upgradable_count=0
min_upgrade_cost=999999

echo "========================================="
echo "  ARMY UPGRADE STATS FOR: $login_original"
echo "========================================="

for id in "${troop_ids[@]}"; do
    # Fetch soldier page and strip Windows carriage returns (\r)
    t_html=$($curl "$site/t/$id" | tr -d '\r')

    # 1. Extract standalone numbers for Money (nums[0]) and Army Power (nums[1])
    mapfile -t nums < <(echo "$t_html" | sed -n 's/^[[:space:]]*\([0-9]\{1,6\}\)[[:space:]]*$/\1/p')

    if [[ ${#nums[@]} -lt 1 ]]; then
        [[ "$probe_mode" -eq 1 ]] && break
        continue
    fi

    t_money="${nums[0]}"
    t_power="${nums[1]:-0}"

    # 2. Parse the exact "Upgrade for <COST>" text from <td class="sheetright">
    t_cost=$(echo "$t_html" | grep -Eoi 'Upgrade for [0-9]+' | grep -Eo '[0-9]+' | head -n 1)

    # Fallback if third standalone number is present and "Upgrade for" wasn't matched
    if [[ -z "$t_cost" && -n "${nums[2]:-}" ]]; then
        t_cost="${nums[2]}"
    fi

    # 3. Extract Soldier Name (from rename input, card alt, or page title)
    t_name=$(echo "$t_html" | sed -n 's/.*id="name" name="name" type="text" value="\([^"]*\)".*/\1/p' | head -n 1)
    if [[ -z "$t_name" ]]; then
        t_name=$(echo "$t_html" | sed -n "s/.*<title>MiniTroopers - \(.*\)&#39;s stats sheet<\/title>.*/\1/p" | head -n 1)
    fi
    [[ -z "$t_name" ]] && t_name="Soldier #$((id + 1))"

    # Capture the account gold and power from the first valid soldier page
    if [[ -z "$money" ]]; then
        money="$t_money"
        army_power="$t_power"
        echo "Current Gold : $money | Army Power : $army_power"
        echo "-----------------------------------------"
    fi

    total_soldiers=$((total_soldiers + 1))

    # Check if we got a valid numeric upgrade cost
    if [[ -n "$t_cost" && "$t_cost" =~ ^[0-9]+$ ]]; then
        if [[ "$t_cost" -lt "$min_upgrade_cost" ]]; then
            min_upgrade_cost="$t_cost"
        fi

        if [[ "$money" -ge "$t_cost" ]]; then
            upgradable_count=$((upgradable_count + 1))
            status="[UPGRADABLE!]"
        else
            needed=$((t_cost - money))
            status="(Needs $needed more gold)"
        fi

        printf "  #%-2d %-14s | Next Upgrade: %-4d gold | %s\n" "$((id + 1))" "($t_name)" "$t_cost" "$status"
    else
        printf "  #%-2d %-14s | Next Upgrade: [Hidden - Army requires password/owner cookie]\n" "$((id + 1))" "($t_name)"
    fi
done

echo "-----------------------------------------"
if [[ "$total_soldiers" -gt 0 ]]; then
    echo "Total Soldiers               : $total_soldiers"
    if [[ "$min_upgrade_cost" -lt 999999 ]]; then
        echo "Upgradable Soldiers Right Now: $upgradable_count / $total_soldiers (with $money gold)"
        echo "Minimum Needed for Next Upgr : $min_upgrade_cost gold"
        if [[ "$money" -ge "$min_upgrade_cost" ]]; then
            echo "Status                       : READY TO UPGRADE AT LEAST 1 SOLDIER!"
        else
            echo "Status                       : Need $((min_upgrade_cost - money)) more gold for cheapest upgrade."
        fi
    else
        echo "Status                       : Could not see 'Upgrade for X' button (check password or cookies.txt)."
    fi
else
    echo "Could not retrieve soldier data for $login_original (check login/password)."
fi
echo "========================================="