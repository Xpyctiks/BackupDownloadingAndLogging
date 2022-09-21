##One more simple backup scripts for *nix-based systems. Written for personal use, but i found them quite useful for backup of my servers, that's why may be somebody will found them useful too.

####Features:
    **backup.sh:**
        -Configuration of folders and DB names to be backed up via configuration file. 
        -Creating daily DB backups and weekly DB+folders backups on client's servers.
        -Creating SHA1 checksums of created archives for future validation after downloading to remote storage.
    **backup-download.sh:**
        -Centralized downloading of daily and weekly backups from remote client's servers.
        -Validation of the downloaded files via SHA1 checksum checking.
        -Configuration of hosts and downloading methods in configuration file.
        -Advanced logging of all actions while working of the script.
        -Writing results of all actions to MySQL DB.
        -Attaching results of backups downloading to Zabbix monitoring with alerts.
    **BackupLogging.sql:**
        -DB init script.
    **zabbix-backuplogging-template.xml:**
        -Two templates for Zabbix.

####Workflow:
    **Client side:**
        -Once per day a script backup.sh if being launched via CRON with "daily" parameter - it's creating a daily databases backups from the list in backup.cfg.
        -Once per week a script backup.sh if being launched via CRON with "weekly" parameter - it's creating a daily databases and folders backups from the list in backup.cfg.
        -After any archives creation process the checksum file database is being created.
    **Storage server side:**
        -Once per day and once per week a script backup-download.sh if being launched via CRON with "daily" and "weekly" parameters - it's downloading a daily databases backups  and/or weekly folders backups from the list in backup-download.cfg.
        -After every downloading, the script checks SHA1 checksums of the downloaded files using sha1.sum file received with remote files.If checksums are OK - it creates file "checksums-OK" inside a directory and writing to MySQL database a record with successfull result of the downloading process.If something goes wrong - the script creates file "checksums-FAILED" inside the dir and writing do DB result with fail result code.
        -Zabbix server calls the script "get-mysql-backup-status.sh" once per day at some time after main backup-download.sh script shoud finish it's work.This script is getting from DB the list of today's results for every domain name-by-name. If any domain name returns result code which is not equal to 0 or the record about this domain absent at all - Zabbix calls trigger with alert.
        -While working, the script "backup-download.sh" is making enough output of all processes it is doing, and being redirected in CRON config to any log file, the script creates very easy debug ability.
        -Records of all download processes in DB are making the review and debug actions very clear and simple.

####Installation:
    **Client side:**
        -Place "backup.cfg" and "backup.sh" files to any folder you want.
        -Add cron task, for example:
        0 7 * * 1-6 /opt/backup/backup.sh daily > /var/log/backup-daily.log
        0 7 * * 0 /opt/backup/backup.sh weekly > /var/log/backup-weekly.log
        This will run daily backups every day from Monday to Saturday at 7:00 (am) and weekly backup every Saturday at 7:00 (am).All working log is being redirected to log file.
        -Configure databases and folder you want to be backed up via backup.cfg file.
    **Storage server side:**
        -Place "backup-download.cfg" and "backup-download.sh" files to any folder you want.
        -In "backup-download.sh" set variables "dbName,dbPass,dbUser,backupFolder,scpUser" to your values.
        -Fill in the backup-download.cfg file with a data of your hosts.
        -Create MySQL database and initialize it using "BackupLogging.sql" template.
        -Add cront tasks, for example:
            0 9 * * 1-6 /opt/backup-download/backup-download.sh daily > /var/log/backup-download.log
            0 9 * * 0 /opt/backup-download/backup-download.sh weekly > /var/log/backup-download.log
        The time of launch shoud be later then client's scripts are starting, to make client's script finish it's job.
        -Import "zabbix-backuplogging-template.xml" to Templates.
        -Copy "get-mysql-backup-status.sh" script to Zabbix external scripts folder.
        -Configure your hosts in Zabbix to use those templates.
