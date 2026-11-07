#!/bin/bash

### FUNCTIONS ###

function grepTrooper {
    $curl "$site/t/$1" \
        | $egrep --regexp='^[0-9]+$'
}

function getMoneyRatio {
	local ratio=($(grepTrooper 0))
	local money="${ratio[0]}"
	local upgrade_cost="${ratio[1]}"

    if [[ "$report" == "always" || \
        ( "$report" == "upgradable" && \
          "$money" -ge "$upgrade_cost" ) ]]; then
        echo "$login's money for next upgrade : $money/$upgrade_cost"
    fi
}

# =========================================================================
# MISSION FUNCTIONS (MODIFIED FOR NEW SERVER)
# =========================================================================

function mission {
    # <<< CHANGED: Iterates through all 3 mission types found on your new homepage
    for type in exterminate infiltrate epic; do
        # <<< CHANGED: Loops 3 times for each mission type
        for i in {1..3}; do
            echo "Running mission ($type) - attempt $i/3..."
            # <<< CHANGED: Updated URL to use ?t=<type>, removed chk= parameter, added > /dev/null
            $curl "$site/b/mission?t=$type" > /dev/null
        done
    done
}

# =========================================================================
# BATTLE FUNCTIONS (ALREADY WORKING)
# =========================================================================

function getFightKey {
    $curl --cookie-jar "$cookie_file" "$site/b/opp" \
        | $egrep --regexp='opp=[0-9]+' \
        | head --lines=1
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
        $curl --data "friend=$1" "$site/b/battle" > /dev/null
    done
}

# =========================================================================

function hasRecruits {
    $curl "'$site/hq'" | grep "$Another" > /dev/null
    return $?
}

function raid {
    while hasRecruits
    do
        $curl "'$site/b/raid?chk=$chk'"
    done
}

function login {
    curl -L --silent --cookie-jar "$cookie_file" --data "$1" "$site/login" > /dev/null
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
source $prefix/troopers.cfg
source $prefix/$ext.culture

## Reading CLI ##
login=$1
password=$2
[[ -n "$3" ]] && friend="$3"

## Script Locals ##
site="https://$login.trooperstest.gued.es"
cookie_file="$(mktemp -t "$login.XXXXXX" --suffix='.cookie')"
curl="curl -L --silent --cookie $cookie_file"
egrep="grep --extended-regexp --only-matching"

## Dependency checks ##
for command in 'grep' 'curl'; do
	which "$command" > /dev/null
	if [[ $? -gt 0 ]]; then
		echo "error: $0 needs $command to execute"
		exit 2
	fi
done

# Login
if [[ -n $password ]]
then
    login "login=$login&pass=$password"
else
    login "login=$login"
fi

chk="$(getCheck "$cookie_file")"

# 1. Execute Battles
if [[ -z "$friend" ]]; then
    fightRandom
else
    fightFriend "$friend"
fi

# 2. Execute Missions
# <<< CHANGED: Uncommented mission so it runs right after battles
mission

# <<< CHANGED: Temporarily keeping raid and money report disabled until missions are verified
# raid &
# wait
# if [[ "$report" != "never" ]]; then
#     getMoneyRatio
# fi

echo "Finished running battles and missions!"
exit 0