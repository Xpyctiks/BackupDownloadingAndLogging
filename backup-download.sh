#!/usr/bin/env bash

NAME=$(/bin/date '+%d.%m.%Y')           #Name of current folder for download - created from current datestamp.
LOG=""                                  #Variable for text for putting in DB as log message.
RESULT="0"                              #Result of completion of operation - 1(fail) or 0(success) for DB write.
DOMAIN=""                               #Domain we are working with (for record to DB).
TYPE=""                                 #Type of operation - Daily or Weekly.
TYPE2=""                                #Type of operation - Daily or Weekly in lower case for some functions.
Color_Off='\033[0m'
Red='\033[0;31m'
Green='\033[0;32m'                      #Variables with text color for output.
Yellow='\033[0;33m'
White='\033[0;37m'
workArr=()                              #Array to be filled by strings with path of our new downloads to set permissions to them in the end.
scpUser="bckp"                          #User for SCP login.
dbUser="BackupLogging"                  #User for access to DB for write logs.
dbPass=""                               #Password for access to DB for write logs.
dbName="BackupLogging"                  #DB name.
configFile="backup-download.cfg"        #Name of the file with list of servers to download backups from.
backupsFolder="/media/crypt-backups"    #Folder where backups will be downloaded.
markerDir="${backupsFolder}/MarkerDir"  #MarkerDir using for make sure the encrypted volume for backups is mounted.Could be removed with checking func. futher.
logDir="/var/log/backup-download"       #Where to store backup log files with output of Rsync working process.
shaFileRem="sha1sum.remote"             #Name of the file with checksum list from remote servers.Important to use with checksum check option.
shaFileLoc="sha1sum.local"              #Name of local file to compare checksums of received files with the remote one.
shaApp="/usr/bin/sha1sum"               #Path and name of app to create checksum. SHA1 default.

#Head to the current directory of the script it has been launched from. Check if we are launched from symlink or any other place as subshell process.
echo "${0}" | egrep -e '^\..*' > /dev/null 2>&1
if [[ "${?}" == "0" ]]; then
    #the script is launched from shell manually
    scriptName=$(echo "${0}" | sed 's/.//')
    scriptPath=$(realpath -e ${0} | sed "s/\\${scriptName}//")
    cd ${scriptPath}
else
    #the script is launched from cron or any parent process
    scriptName=$(basename ${0})
    scriptPath=$(echo "${0}" | sed "s/${scriptName}//")
    cd ${scriptPath}
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

#Check do we have parameters and are they correct
if [[ -z "${1}" ]]; then 
    echo -e "${Yellow}Usage: ${0} <type>"
    echo -e  "Type:\n\t${White}daily${Yellow} - download daily backups\n\t${White}weekly${Yellow} - download weekly backups${Color_Off}"
    exit 1
elif [[ "${1}" == "daily" ]] || [[ "${1}" == "Daily" ]]; then
    TYPE="Daily"
    TYPE2="daily"
elif [[ "${1}" == "weekly" ]] || [[ "${1}" == "Weekly" ]]; then
    TYPE="Weekly"
    TYPE2="weekly"
else
    echo -e "${Red}Unknown parameter!${Color_Off}"
    exit 1
fi

#Logging to DB function. ${TYPE} means name of table in there - Daily or Weekly
function Log() {
mysql -u${dbUser} -p${dbPass} ${dbName} << EOF
INSERT INTO ${TYPE} (Domain, Type, Result, Critical, Message) VALUES ("$1","$2","$3","$4","$5");
EOF
}

#Check does the MarkerDir exists - if not, that means encrypted partition is not mounted. Delete this function if you are not using encrypted partitions.
if ! [[ -d "${markerDir}" ]]; then
    LOG+="$(/bin/date '+%d.%m.%Y %H:%m:%S') backups volume not mounted! Exiting!"
    echo -e "${Red}${LOG}${Color_Off}"
    Log "-" "-" "1" "1" "$LOG"
    exit 1
fi

#Check does the logDir exist and create it if it's not
if ! [[ -d "${logDir}" ]]; then
    mkdir -p ${logDir}
fi

function downloadRsync()
{
    local hostName=${1}
    local dnsName=${2}
    echo -e "${Yellow}Starting ${White}Rsync${Yellow} download ${White}${TYPE2}${Yellow} backups from ${White}${hostName}${Yellow} as ${White}${dnsName}${Yellow}...${Color_Off}"
    LOG=""
    #check the type of allowed actions with host - "daily" only, "weekly" only, "all"
    if [[ ${hostType} != "${TYPE2}" ]] && [[ ${hostType} != "all" ]]; then
        echo -e "${Red}Host ${Yellow}${hostName}${Red} is not allowed to use ${TYPE} downloading. Skipping...${Color_Off}"
        continue
    fi
    echo -e "${Yellow}\tHeading to ${backupsFolder}/${hostName}/${TYPE2}/...${Color_Off}"
    cd ${backupsFolder}/${hostName}/${TYPE2}/
    if [[ "${?}" == "0" ]]; then
        echo -e "${Yellow}\tDoing rsync -raP --delete ${scpUser}@${dnsName}:/var/www/ ${backupsFolder}/${hostName}/${TYPE2}/ > /dev/null 2>&1${Color_Off}"
        #Adding starting header to log file.
        echo "------------------------------------Started $(/bin/date '+%d.%m.%Y %H:%m:%S') ${hostName}--------------------------------------" >> ${logDir}/${NAME}-${TYPE2}.log
        echo -e "${Yellow}Backup folder size BEFORE: $(du -sh ${backupsFolder}/${hostName}/${TYPE2}/)${Color_Off}"
        rsync -raP --delete ${scpUser}@${dnsName}:/var/www/ ${backupsFolder}/${hostName}/${TYPE2}/ >> ${logDir}/${NAME}-${TYPE2}.log
		if [[ "$?" == "0" ]]; then
		    #Here and futher - adding text to the special variable, which will be written to DB in the end.
            LOG+="${hostName} done successfully!"
            echo -e "${Yellow}\tBackup folder size AFTER: $(du -sh ${backupsFolder}/${hostName}/${TYPE2}/)${Color_Off}"
            #Setting up secure permissions
            chmod 700 ${backupsFolder}/${hostName}/${TYPE2}/
            echo -e "${White}${hostName}${Green} done successfully!${Color_Off}"
            #Writing to our DB result with codes and text from the variable
		    Log "${hostName}" "${TYPE}" "0" "0" "${LOG}"
            #Adding finishing trailer to log file.
            echo "------------------------------------Finished $(/bin/date '+%d.%m.%Y %H:%m:%S') ${hostName}--------------------------------------" >> ${logDir}/${NAME}-${TYPE2}.log
		else
		    LOG+="\n"
		    LOG+="${hostName} error while downloading!"
            echo -e "${Red}${hostName} error while downloading!${Color_Off}"
            #Writing to our DB result with codes and text from the variable
		    Log "${hostName}" "${TYPE}" "1" "0" "${LOG}"
            #Adding finishing trailer to log file.
            echo "------------------------------------Finished $(/bin/date '+%d.%m.%Y %H:%m:%S') ${hostName}--------------------------------------" >> ${logDir}/${NAME}-${TYPE2}.log
		fi
    else
        LOG+="${hostName} error changing dir to ${backupsFolder}/${hostName}/${TYPE2}/!"
        Log "${hostName}" "${TYPE}" "1" "1" "${LOG}"
    fi
}

function downloadScp()
{
    local hostName=${1}
    local dnsName=${2}
    echo -e "${Yellow}Starting ${White}SCP${Yellow} download ${White}${TYPE2}${Yellow} backups from ${White}${hostName}${Yellow} as ${White}${dnsName}${Yellow}...${Color_Off}"
    LOG=""
    #if current day folder not exists - create it
    if [[ ! -d "${backupsFolder}/${hostName}/${TYPE2}/${NAME}" ]]; then
        mkdir -p ${backupsFolder}/${hostName}/${TYPE2}/${NAME}
    fi
    echo -e "${Yellow}\tHeading to ${backupsFolder}/${hostName}/${TYPE2}/${NAME}...${Color_Off}"
    cd ${backupsFolder}/${hostName}/${TYPE2}/${NAME}
    if [[ "${?}" == "0" ]]; then
        #Clearing folder.We don't need anything unexpected in our folder.
        rm -f * > /dev/null 2>&1
        echo -e "${Yellow}\tDoing scp ${scpUser}@${dnsName}:/home/backup/${TYPE2}/${NAME}/* . 2>&1${Color_Off}"
        LOG+=$(scp ${scpUser}@${dnsName}:/home/backup/${TYPE2}/${NAME}/* . 2>&1)
		if [[ "$?" == "0" ]]; then
            #If folder with backups has special sha1 checksums file - do the check
            if [[ -f "${shaFileRem}" ]] && [[ -f "${shaApp}" ]]; then
                #Creating local checksums list
                ${shaApp} *.gz > ${shaFileLoc}
                #Comparing with received file from remote server
                diff ${shaFileRem} ${shaFileLoc} > /dev/null
                if [[ "$?" == "0" ]]; then
                    LOG+="${hostName} done successfully! Checksums ok!"
                    echo -e "${Green}${hostName} done successfully! Checksums ok! Backup folder size: $(du -sh ${backupsFolder}/${hostName}/${TYPE2}/${NAME})${Color_Off}"
                    workArr+=("${backupsFolder}/${hostName}/${TYPE2}/${NAME}")
                    Log "${hostName}" "${TYPE}" "0" "0" "${LOG}"
                    rm -f ${shaFileLoc} > /dev/null
                    #Creating file which make us able to see that everything in this directory is ok
                    touch sha1sum-OK
                else
                    LOG+="${hostName} done successfully! But checksums are NOT ok!"
                    echo -e "${Green}${hostName} done successfully!${Yellow} But checksums are NOT ok!${Green} Backup folder size: $(du -sh ${backupsFolder}/${hostName}/${TYPE2}/${NAME})${Color_Off}"
                    workArr+=("${backupsFolder}/${hostName}/${TYPE2}/${NAME}")
                    Log "${hostName}" "${TYPE}" "2" "0" "${LOG}"
                    #Creating file which make us able to see that in this directory we have problems with backups
                    touch sha1sum-FAILED
                fi
            else
                #If no checksum file in directory or problems with sha1 check executable file
                if ! [[ -f "${shaApp}" ]]; then
                    LOG+="${hostName} done successfully! Program ${shaApp} not found! Unable to check checksums!"
                    echo -e "${Green}${hostName} done successfully!${Yellow} Program ${shaApp} not found! Unable to check checksums!${Green} Backup folder size: $(du -sh ${backupsFolder}/${hostName}/${TYPE2}/${NAME})${Color_Off}"
                else
                    LOG+="${hostName} done successfully! No checksums file to check!"
                    echo -e "${Green}${hostName} done successfully! ${Yellow}No checksums file found! ${Green}Backup folder size: $(du -sh ${backupsFolder}/${hostName}/${TYPE2}/${NAME})${Color_Off}"
                fi
                workArr+=("${backupsFolder}/${hostName}/${TYPE2}/${NAME}")
                Log "${hostName}" "${TYPE}" "2" "0" "${LOG}"
            fi
		else
		    LOG+="\n"
		    LOG+="${hostName} error while downloading!"
            echo -e "${Red}${hostName} error while downloading!${Color_Off}"
		    Log "${hostName}" "${TYPE}" "1" "0" "${LOG}"
		fi
    else
        LOG+="${hostName} error changing dir to ${backupsFolder}/${hostName}/${TYPE2}/${NAME}!"
        echo -e "${Red}${LOG}${Color_Off}"
        Log "${hostName}" "${TYPE}" "1" "1" "${LOG}"
    fi
}

#Function sets permissions to folders from workArr() variable and files inside them.
function updatePermissions()
{
    for (( i=0; i < ${#workArr[@]}; i++))
    {
        chmod 700 ${workArr[${i}]}
        if [[ "${?}" != "0" ]]; then
            echo -e "${Red}\tUnexpected error while setting up folder permission on ${workArr[${i}]}${Color_Off}"
        fi
        chmod 600 ${workArr[${i}]}/*
        if [[ "${?}" != "0" ]]; then
            echo -e "${Red}\tUnexpected error while setting up files permissions on ${workArr[${i}]}/*${Color_Off}"
        fi
        echo -e "${Yellow}${workArr[${i}]} setting of permissions done.${Color_Off}"
    }
}

#Main function.Everything starts here.
echo -e "${Green}------------------------------------------$(/bin/date '+%d.%m.%Y %H:%m:%S') Starting new tasks:------------------------------------------${Color_Off}"
#Reading  config file and parsing it
while read hostName dnsName hostType dailyType weeklyType; do
    #Skipping comments strings - if anywhere is # symbol.
    if [[ "${hostName}" == *"#"* ]] || [[ "${dnsName}" == *"#"* ]] || [[ "${hostType}" == *"#"* ]] || [[ "${dailyType}" == *"#"* ]] || [[ "${weeklyType}" == *"#"* ]]; then
        continue
    fi
    #Check do all variables are filled by data. If not, shows up error and skipping this string
    if [[ -z "${hostName}" ]] || [[ -z "${dnsName}" ]] || [[ -z "${hostType}" ]] || [[ -z "${dailyType}" ]] || [[ -z "${weeklyType}" ]]; then
        echo -e "${Red}Error parsing string ${hostName} from the config file!"
        continue
    fi
    #Download for Daily and Weekly type with SCP 
    if [ "${hostType}" == "${TYPE2}" ] || [ "${hostType}" == "all" ]; then
        #Daily backup via scp
        if  ([ "${TYPE2}" == "daily" ] && [ "${dailyType}" == "scp" ]); then
            downloadScp ${hostName} ${dnsName}
            continue
        #Weekly backup via scp
        elif ([ "${TYPE2}" == "weekly" ] && [ "${weeklyType}" == "scp" ]); then
            downloadScp ${hostName} ${dnsName}
            continue
        #Daily backup via rsync
        elif ([ "${TYPE2}" == "daily" ] && [ "${dailyType}" == "rsync" ]); then
            downloadRsync ${hostName} ${dnsName}
            continue
        #Weekly backup via rsync
        elif ([ "${TYPE2}" == "weekly" ] && [ "${weeklyType}" == "rsync" ]); then
            downloadRsync ${hostName} ${dnsName}
            continue
        fi
    else
        echo -e "${Red}Host ${Yellow}${hostName}${Red} is not allowed to use ${TYPE} downloading. Skipping...${Color_Off}"
        continue
    fi
done <<< $(cat ${configFile})
#Updating mode for files and folder to secure values
echo -e "${Yellow}Almost done. Setting up correct permissions on backups...${Color_Off}"
updatePermissions
echo -e "${Green}------------------------------------------$(/bin/date '+%d.%m.%Y %H:%m:%S') All tasks done successfully!------------------------------------------${Color_Off}"
