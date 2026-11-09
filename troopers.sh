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
    $curl --cookie-jar "$cookie_file" "$site/b/opp" | $egrep --regexp='opp=[0-9]+' | head --lines=1 
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