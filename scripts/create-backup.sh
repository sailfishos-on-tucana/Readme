#!/bin/bash -x
DATE=$(date +"%Y%m%d-%H%M%S")
BACKUP=sfe-backup-$DATE.tar.gz
echo Creating backup $BACKUP 
adb shell tar --numeric-owner -czf /data/backup/$BACKUP -C /data/.stowaways/sailfishos .
adb pull /data/backup/$BACKUP
