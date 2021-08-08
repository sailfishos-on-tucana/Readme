#!/bin/bash -x
set -e

# Unbzips and uploads a tar image through adb
# Run from the same folder as the sfe-tucana-*.tar.bz2
# like RELEASE=4.0.1.48 EXTRA_NAME=alpha ../publish-sfe.sh 

EXTRA_NAME=${EXTRA_NAME:=-prerelease}
echo publishing $RELEASE$EXTRA_NAME
sudo bunzip2 -vf sfe-tucana-$RELEASE$EXTRA_NAME.tar.bz2
adb shell mkdir -p /data/.stowaways/sailfishos
adb shell rm -r /data/.stowaways/sailfishos/\*
adb push sfe-tucana-$RELEASE$EXTRA_NAME.tar /sdcard/
adb shell tar --numeric-owner -xf /sdcard/sfe-tucana-$RELEASE$EXTRA_NAME.tar -C /data/.stowaways/sailfishos
