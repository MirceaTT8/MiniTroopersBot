#!/bin/bash

### FUNCTIONS ###

function grepTrooper {
    $curl "$site/t/$1" | $egrep --regexp='^[0-9]+$'
}

function getMoneyRatio {
    local ratio=($(grepTrooper 0))
    local money="${ratio[0]}"
    local upgrade_cost="${ratio[1]}"
    if [[ "$report" == "always" || ( "$report" == "upgradable" && "$money" -ge "$upgrade_cost" ) ]]; then
        echo "$login_original's money for next upgrade : $money/$upgrade_cost"
    fi
}

# =========================================================================
# MISSION FUNCTIONS
# =========================================================================
function mission {
    echo "========================================="
    echo "Starting Missions phase..."

    for type in exterminate infiltrate epic; do
        # Map mission type to its specific tooltip ID on /hq
        local tip_id=""
        case "$type" in
            exterminate) tip_id="miss_tip" ;;
            infiltrate)  tip_id="infil_tip" ;;
            epic)        tip_id="epic_tip" ;;
        esac

        for i in {1..3}; do
            local hq_html=$($curl "$site/hq")

            # If the mission button for this type is no longer on /hq,
            # the mission is either already won or out of attempts for today.
            if ! echo "$hq_html" | grep -q "mission?t=$type"; then
                echo "  Mission ($type) - no more attempts available today."
                break
            fi

            echo -n "  Running mission ($type) - attempt $i/3... "
            $curl "$site/b/mission?t=$type" > /dev/null

            # Fetch updated /hq and inspect the latest badge for this mission's tip_id
            local updated_hq=$($curl "$site/hq")
            local last_badge=$(echo "$updated_hq" | grep "$tip_id" | grep -Eo 'b(win|defeat)_bg' | tail -n 1)

            if [[ "$last_badge" == "bwin_bg" ]]; then
                echo "WON!"
            else
                echo "LOST!"
            fi
        done
    done
}

# =========================================================================
# BATTLE FUNCTIONS
# =========================================================================
function getFightKey {
    # 1. Download the opponent page HTML
    local opp_html=$($curl --cookie-jar "$cookie_file" "$site/b/opp")

    # 2. Parse in the exact HTML order:
    #    backchoose -> tcard (soldiers) -> opp= (ID) -> po (power)
    local best_opp=$(echo "$opp_html" | awk '
        BEGIN {
            best_opp = ""
            min_avg = 999999
            troops = 0
            current_opp = ""
            in_po = 0
        }

        # Step A: Start of a new enemy card — reset variables
        /class="backchoose"/ {
            troops = 0
            current_opp = ""
            in_po = 0
        }

        # Step B: Count every soldier card (works even if multiple are on 1 line)
        /class="tcard"/ {
            line = $0
            while (match(line, /class="tcard"/)) {
                troops++
                line = substr(line, RSTART + RLENGTH)
            }
        }

        # Step C: Grab the opponent ID (do NOT reset troops here!)
        /opp=[0-9]+/ {
            if (match($0, /opp=[0-9]+/)) {
                current_opp = substr($0, RSTART, RLENGTH)
            }
        }

        # Step D: Detect the Power section
        /<li class="po">/ {
            in_po = 1
        }

        # Step E: Read the power value and immediately calculate the average
        in_po && /^[ \t]*[0-9]+[ \t]*$/ {
            line = $0
            gsub(/[^0-9]/, "", line)
            power = line + 0

            if (current_opp != "" && troops > 0 && power > 0) {
                avg = power / troops
                # Debug print to stderr so you can see the math in your terminal!
                printf "  [Eval] %-12s | Power: %2d | Troops: %d | Avg: %.2f\n", current_opp, power, troops, avg > "/dev/stderr"

                if (avg < min_avg) {
                    min_avg = avg
                    best_opp = current_opp
                }
            }
            in_po = 0
        }

        END {
            if (best_opp != "") {
                printf "  [Selected] %s (Lowest Avg: %.2f)\n", best_opp, min_avg > "/dev/stderr"
                print best_opp
            }
        }
    ')

    # 3. Return the best opponent or fallback if parsing fails
    if [[ -n "$best_opp" ]]; then
        echo "$best_opp"
    else
        echo "$opp_html" | $egrep --regexp='opp=[0-9]+' | head --lines=1
    fi
}

function fightRandom {
    echo "========================================="
    echo "Starting Battles phase (Random)..."
    for i in {1..6}; do
        local key="$(getFightKey)"
        if [[ -n "$key" ]]; then
            echo -n "  Battle $i/6: Attacking opponent ($key)... "
            $curl "$site/b/battle?$key" > /dev/null

            # Check the newest 'bat_tip' result badge on /hq
            local last_bat=$($curl "$site/hq" | grep "bat_tip" | grep -Eo 'b(win|defeat)_bg' | tail -n 1)
            if [[ "$last_bat" == "bwin_bg" ]]; then
                echo "WON!"
            else
                echo "LOST!"
            fi
        else
            echo "  Battle $i/6: No opponent found on /b/opp (0 battles left or page error)."
            break
        fi
    done
}

function fightFriend {
    echo "========================================="
    echo "Starting Battles phase (Friend: $1)..."
    for i in {1..6}; do
        # Check if battles are already on cooldown (initMissionTimer(1))
        if $curl "$site/hq" | grep -q "initMissionTimer(1)"; then
            echo "  Battle $i/6: No battles left today."
            break
        fi

        echo -n "  Battle $i/6: Attacking friend ($1)... "
        $curl --data-urlencode "friend=$1" "$site/b/battle" > /dev/null

        local last_bat=$($curl "$site/hq" | grep "bat_tip" | grep -Eo 'b(win|defeat)_bg' | tail -n 1)
        if [[ "$last_bat" == "bwin_bg" ]]; then
            echo "WON!"
        else
            echo "LOST!"
        fi
    done
}

# =========================================================================
# RAID FUNCTIONS
# =========================================================================
function hasRecruits {
    $curl "$site/hq" | grep "$Another" > /dev/null
    return $?
}

function raid {
    echo "========================================="
    echo "Starting Raids phase..."
    for i in {1..9}; do
        if $curl "$site/hq" | grep 'href="/b/raid"' > /dev/null; then
            echo -n "  Raid $i: Recruits available! Executing raid... "
            $curl "$site/b/raid" > /dev/null

            local last_raid=$($curl "$site/hq" | grep "raid_tip" | grep -Eo 'b(win|defeat)_bg' | tail -n 1)
            if [[ "$last_raid" == "bwin_bg" ]]; then
                echo "STAGE CLEARED!"
            else
                echo "DEFEATED!"
            fi
        else
            echo "  Raids complete (0 recruits available)."
            break
        fi
    done
}

# =========================================================================
# DAILY SUMMARY REPORT (PARSED DIRECTLY FROM /hq)
# =========================================================================
function printSummary {
    local hq_html=$($curl "$site/hq")

    # 1. Battle stats ('bat_tip')
    local bat_wins=$(echo "$hq_html" | grep "bat_tip" | grep -c "bwin_bg")
    local bat_losses=$(echo "$hq_html" | grep "bat_tip" | grep -c "bdefeat_bg")
    local bat_total=$((bat_wins + bat_losses))
    local bat_pct="0.00"
    if [[ "$bat_total" -gt 0 ]]; then
        bat_pct=$(awk "BEGIN { printf \"%.2f\", ($bat_wins / $bat_total) * 100 }")
    fi

    # 2. Mission stats ('miss_tip', 'infil_tip', 'epic_tip')
    local ext_wins=$(echo "$hq_html" | grep "miss_tip" | grep -c "bwin_bg")
    local ext_loss=$(echo "$hq_html" | grep "miss_tip" | grep -c "bdefeat_bg")
    local ext_tot=$((ext_wins + ext_loss))

    local inf_wins=$(echo "$hq_html" | grep "infil_tip" | grep -c "bwin_bg")
    local inf_loss=$(echo "$hq_html" | grep "infil_tip" | grep -c "bdefeat_bg")
    local inf_tot=$((inf_wins + inf_loss))

    local epic_wins=$(echo "$hq_html" | grep "epic_tip" | grep -c "bwin_bg")
    local epic_loss=$(echo "$hq_html" | grep "epic_tip" | grep -c "bdefeat_bg")
    local epic_tot=$((epic_wins + epic_loss))

    local total_m_wins=$((ext_wins + inf_wins + epic_wins))

    # 3. Raid Phase ('<h1 class="hbox">Raid Phase X</h1>')
    local raid_phase=$(echo "$hq_html" | grep -Eo '<h1 class="hbox">Raid Phase [0-9]+</h1>' | grep -Eo '[0-9]+')
    [[ -z "$raid_phase" ]] && raid_phase="Unknown"

    echo "========================================="
    echo "       SUMMARY FOR: $login_original"
    echo "========================================="
    echo "Battles Won     : $bat_wins/$bat_total ($bat_pct%)"
    echo "Missions Won    : $total_m_wins/3 missions completed"
    echo "  - Exterminate : $ext_wins won ($ext_loss failed, $ext_tot attempts)"
    echo "  - Infiltrate  : $inf_wins won ($inf_loss failed, $inf_tot attempts)"
    echo "  - Epic        : $epic_wins won ($epic_loss failed, $epic_tot attempts)"
    echo "Last Raid Level : Raid Phase $raid_phase"
    echo "========================================="
}

function authenticate {
    # Uses --data-urlencode to safely handle special characters like @, &, =, ! in passwords
    if [[ -n "$password" ]]; then
        curl -L --silent --cookie-jar "$cookie_file" \
            --data-urlencode "login=$login_lower" \
            --data-urlencode "pass=$password" \
            "$site/login" > /dev/null
    else
        curl -L --silent --cookie-jar "$cookie_file" \
            --data-urlencode "login=$login_lower" \
            "$site/login" > /dev/null
    fi
}

function cleanup {
    rm --force "$cookie_file"
}

trap "cleanup" EXIT

### VARIABLES ###
## Defaults ##
prefix="$(dirname "$0")"
ext="com"
Another="Another"
report="upgradable"

## Reading config files ##
[[ -f "$prefix/troopers.cfg" ]] && source "$prefix/troopers.cfg"
[[ -f "$prefix/$ext.culture" ]] && source "$prefix/$ext.culture"

## Reading CLI ##
if [[ -z "$1" ]]; then
    echo "Usage: $0 <login> [password] [friend]"
    exit 1
fi

login_original="$1"
password="$2"
[[ -n "$3" ]] && friend="$3"

# Force login to lowercase for URLs and authentication
login_lower=$(echo "$login_original" | tr '[:upper:]' '[:lower:]')

## Script Locals ##
site="https://$login_lower.trooperstest.gued.es"
cookie_file="$(mktemp -t "$login_lower.XXXXXX" --suffix='.cookie')"
curl="curl -L --silent --cookie $cookie_file"
egrep="grep --extended-regexp --only-matching"

## Dependency checks ##
for command in 'grep' 'curl' 'awk' 'tr'; do
    if ! command -v "$command" > /dev/null; then
        echo "error: $0 needs $command to execute"
        exit 2
    fi
done

# 0. Authenticate
authenticate

# 1. Execute Battles
if [[ -z "$friend" ]]; then
    fightRandom
else
    fightFriend "$friend"
fi

# 2. Execute Missions
mission

# 3. Execute Raids
raid

# 4. Print Final Summary & Upgrade Money Ratio
printSummary

if [[ "$report" != "never" ]]; then
    getMoneyRatio
fi

echo "Finished running battles, missions, and raids!"
exit 0