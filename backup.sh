#!/bin/env bash

DATE=$(/bin/date '+%d.%m.%Y %H:%M:%S') #Date to use for logging.
NAME=$(/bin/date '+%d.%m.%Y')          #Name for folders we are working with.
Color_Off='\033[0m'
Red='\033[0;31m'
Green='\033[0;32m'                     #Colors for text to console.
Yellow='\033[0;33m'
White='\033[0;37m'
configFile="backup.cfg"                #Name of the config file with list of backup sources.
backupsFolder="/home/backup"           #Directory where the backups are stored.
logDir="/var/log/backup"               #Where to place log file with our work.
type=""                                #Type of the action - daily or weekly.
pathArr=()                             #Array with paths to be backed up.
dbArr=()                               #Array with DB names to be dumped.
shaFileRem="sha1sum.remote"            #Name of a file with checksums of all created backups.
shaApp="/usr/bin/sha1sum"              #Path and name of app to create checksum. SHA1 default.

#Head to the current directory of the script it has been launched from. Check if we are launched from symlink or any other place as subshell process.
echo "${0}" | egrep -e '^\..*' > /dev/null 2>&1
if [[ "${?}" == "0" ]]; then
    #The script is launched from shell manually
    scriptName=$(echo "${0}" | sed 's/.//')
    scriptPath=$(realpath -e ${0} | sed "s/\\${scriptName}//")
    cd ${scriptPath}
else
    #The script is launched from cron or any parent process
    scriptName=$(basename ${0})
    scriptPath=$(echo "${0}" | sed "s/${scriptName}//")
    cd ${scriptPath}
fi

#Check do we have a parameters and they are correct
if [[ -z "${1}" ]]; then
    echo -e "${Yellow}Usage: ${0} <type>"
    echo -e  "Type:\n\t${White}daily${Yellow} - create daily backups\n\t${White}weekly${Yellow} - create weekly backups${Color_Off}"
    exit 1
elif [[ "${1}" != "daily" ]] && [[ "${1}" != "weekly" ]]; then
    echo -e "${Red}Unknown parameter!${Color_Off}"
    exit 1
fi

#Check the config file
if ! [[ -f "${configFile}" ]]; then
    echo -e "${Red}File ${configFile} not found!\nCan't continue...${Color_Off}"
    exit 1
else
    if ! [[ -s "${configFile}" ]]; then
        echo -e "${Red}File ${configFile} is empty!\nCan't continue...${Color_Off}"
        exit 1
    fi
fi

#getting all necessary info from config file
while read parameter value; do
    #Skipping comments strings - if anywhere is # symbol.
    if [[ "${parameter}" == *"#"* ]] || [[ "${value}" == *"#"* ]]; then
        continue
    fi
    #Parsing the config file and filling our arrays with data.
    if [[ ! -z "${parameter}" ]] && [[ ! -z "${value}" ]]; then
        if [[ ${parameter} == "db:" ]]; then
            dbArr+=("${value}")
        elif [[ ${parameter} == "backup:" ]]; then
            pathArr+=("${value}")
        else
            echo -e "${Red}Skipping string with wrong data: ${parameter} ${value}${Color_Off}"
        fi
    else
        echo -e "${Red}Skipping wrong string: ${parameter} ${value}${Color_Off}"
    fi
done <<< $(cat ${configFile})

#Checking do our arrays are filled in by data
if ([ "${#pathArr[@]}" == "0" ] && [ "${#dbArr[@]}" == "0" ]); then
    echo -e "${Red}Both DB and Path arrays are empty.That means you have problems with data in config file.Interrupting...${Color_Off}"
    exit 1
fi

#Main function that processes the main task
if [[ "${1}" == "daily" ]]; then
    echo -e "${Green}----------------${DATE} Starting daily backups-----------------${Color_Off}"
    if [[ ! -d "${backupsFolder}/daily/${NAME}" ]]; then
        mkdir -p ${backupsFolder}/daily/${NAME}
    fi
    cd ${backupsFolder}/daily/${NAME}
    if [[ "${?}" == "0" ]]; then
        #if dbArray is not empty - doing dumps.If it is - skipping and go to all-databases backup
        if [[ ${#dbArr[@]} -gt 0 ]]; then
            #making dumps from list from dbArray
            for (( i=0; i < ${#dbArr[@]}; i++))
            {
                mysqldump --add-drop-database ${dbArr[${i}]} > ${dbArr[${i}]}.sql
                if [[ "${?}" != "0" ]]; then
                echo -e "${Red}\tUnexpected error while creating dump of ${dbArr[${i}]}!Skipping...${Color_Off}"
                fi
                echo -e "${Yellow}\tDB ${dbArr[${i}]} completed...${Color_Off}"
            }
            echo -e "${Yellow}\tDB dumps completed! Moving on...${Color_Off}"
        fi
        #Making dump for All-databases
        mysqldump --all-databases --add-drop-database > AllDB-daily.sql
        if [[ "${?}" != "0" ]]; then
            echo -e "${Red}\tUnexpected error while creating All-databases backup!Skipping...${Color_Off}"
        fi
        echo -e "${Yellow}\tAll-databases dump completed! Moving on...${Color_Off}"
        #Compressing all dumps and removing the originals if success
        while read name; do
            tar -czf ${name}.tar.gz ${name} > /dev/null 2>&1
            if [[ "${?}" == "0" ]]; then
                rm ${name}
            fi
        done <<< $(ls *.sql)
        echo -e "${Yellow}\tDB dumps compression done! Moving on...${Color_Off}"
        #If everything is ok with our SHA1 app - creating checksums
        if [[ -f "${shaApp}" ]]; then
            ${shaApp} *.gz > ${shaFileRem}
            echo -e "${Yellow}\tSHA1 checksums creation done!${Color_Off}"
        else
            echo -e "${Red}\t${shaApp} not found! Checksum file not created!${Color_Off}"
        fi
    fi
    echo -e "${Green}----------------All tasks completed successfully!----------------${Color_Off}"
    exit 0
fi

if [[ "${1}" == "weekly" ]]; then
    echo -e "${Green}-----------------${DATE} Starting weekly backups-----------------${Color_Off}"
    if [[ ! -d "${backupsFolder}/weekly/${NAME}" ]]; then
        mkdir -p ${backupsFolder}/weekly/${NAME}
    fi
    cd ${backupsFolder}/weekly/${NAME}
    if [[ "${?}" == "0" ]]; then
        #making dumps from list from dbArray
        for (( i=0; i < ${#dbArr[@]}; i++))
        {
            mysqldump --add-drop-database ${dbArr[${i}]} > ${dbArr[${i}]}.sql
            if [[ "${?}" != "0" ]]; then
              echo -e "${Red}\tUnexpected error while creating dump of ${dbArr[${i}]}!Skipping...${Color_Off}"
            fi
            echo -e "${Yellow}\tDB ${dbArr[${i}]} completed...${Color_Off}"
        }
        echo -e "${Yellow}\tDB dumps completed! Moving on...${Color_Off}"
        #making dump for All-databases
        mysqldump --all-databases --add-drop-database > AllDB-daily.sql
        if [[ "${?}" != "0" ]]; then
            echo -e "${Red}\tUnexpected error while creating All-databases backup!Skipping...${Color_Off}"
        fi
        echo -e "${Yellow}\tAll-databases dump completed! Moving on...${Color_Off}"
        #compressing all dumps and removing the original one if success
        while read name; do
            tar -czf ${name}.tar.gz ${name} > /dev/null 2>&1
            if [[ "${?}" == "0" ]]; then
                rm ${name}
            fi
        done <<< $(ls *.sql)
        echo -e "${Yellow}\tDB dumps compression done! Moving on...${Color_Off}"
        #making backups from list from pathArray
        for (( i=0; i < ${#pathArr[@]}; i++))
        {
            tar -czf ${pathArr[${i}]}.tar.gz ${pathArr[${i}]} > /dev/null 2>&1
            if [[ "${?}" != "0" ]]; then
              echo -e "${Red}\tUnexpected error while creating backups of ${pathArr[${i}]}!Skipping...${Color_Off}"
            fi
            echo -e "${Yellow}\tBackup of ${pathArr[${i}]} completed...${Color_Off}"
        }
        echo -e "${Yellow}\tAll backups done! Moving on...${Color_Off}"
        if [[ -f "${shaApp}" ]]; then
            ${shaApp} *.gz > ${shaFileRem}
            echo -e "${Yellow}\tSHA1 checksums creation done!${Color_Off}"
        else
            echo -e "${Red}\t${shaApp} not found! Checksum file not created!${Color_Off}"
        fi
    fi
    echo -e "${Green}-----------------All weekly tasks completed successfully!-----------------${Color_Off}"
    exit 0
fi
