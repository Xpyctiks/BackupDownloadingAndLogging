#!/bin/env bash

DATE=$(/bin/date '+%Y.%m.%d')
dbUser="zabbix"
dbPass=""
dbName="BackupLogging"

if [[ -z "${dbName}" ]] || [[ -z "${dbPass}" ]] || [[ -z "${dbUser}" ]]; then
    echo "Some variable(s) is empty in the script!"
    exit 1
fi

if ! [[ -z "${1}" ]] && [[ ${#1} -gt 12 ]]; then
	echo "Too long parameter!"
	exit 1
elif [[ -z "${1}" ]]; then
    echo "No parameter defined!"
    exit 1
fi

if [[ ! -z "$2" ]]; then
    if [ ${#2} -gt 22 ]; then
	    echo "Too long domain name"
	    exit 1
    fi
else
    echo "Domain is not defined"
    exit 1
fi

case "${1}" in
todayLog)
    RES=$(mysql -u${dbUser} -p${dbPass} -e "USE ${dbName};SELECT Result FROM Daily WHERE Date='${DATE}' AND Domain='${2}' LIMIT 1;" | tail -1)
    if [[ -z "${RES}" ]]; then
        echo "255"
    else
        echo "${RES}"
    fi
    ;;
weeklyLog)
    RES=$(mysql -u${dbUser} -p${dbPass} -e "USE ${dbName};SELECT Result FROM Weekly WHERE Date='${DATE}' AND Domain='${2}' LIMIT 1;" | tail -1)
    if [[ -z "${RES}" ]]; then
        echo "255"
    else
        echo "${RES}"
    fi
    ;;
*)
    echo "No such command!"
    exit 1
    ;;
esac
