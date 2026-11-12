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
    for type in exterminate infiltrate epic; do         
        for i in {1..3}; do             
            echo "Running mission ($type) - attempt $i/3..."             
            $curl "$site/b/mission?t=$type" > /dev/null         
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
    for i in {1..6}; do         
        local key="$(getFightKey)"         
        if [[ -n "$key" ]]; then             
            echo "Battle $i/6: Attacking opponent ($key)..."             
            $curl "$site/b/battle?$key" > /dev/null         
        else             
            echo "Battle $i/6: No opponent found on /b/opp (0 battles left or page error)."             
            break         
        fi     
    done 
}

function fightFriend {     
    for i in {1..6}; do         
        echo "Battle $i/6: Attacking friend ($1)..."         
        $curl --data-urlencode "friend=$1" "$site/b/battle" > /dev/null     
    done 
}

# ========================================================================= 
function hasRecruits {     
    $curl "'$site/hq'" | grep "$Another" > /dev/null     
    return $? 
}

function raid {     
    echo "Starting Raids phase..."     
    for i in {1..9}; do         
        if $curl "$site/hq" | grep 'href="/b/raid"' > /dev/null; then             
            echo "Raid $i: Recruits available! Executing raid..."             
            $curl "$site/b/raid" > /dev/null         
        else             
            echo "Raids complete (0 recruits available)."
            break         
        fi     
    done 
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
for command in 'grep' 'curl'; do 
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

# 4. Report Money
if [[ "$report" != "never" ]]; then     
    getMoneyRatio 
fi 

echo "Finished running battles and missions!" 
exit 0