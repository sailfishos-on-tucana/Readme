Building Notes

1. PlatformSDK
2. Android

1. PlatformSDK
   ===
in `~/.hadk.env`
```
export ANDROID_ROOT="$HOME/hadk"
export VENDOR="xiaomi"
export DEVICE="tucana"
export PORT_ARCH="aarch64"
export RELEASE="4.4.0.58"
export EXTRA_NAME="-prerelease"
sudo mount --bind /parentroot/mnt/lineage/hadk /home/vlad/hadk 
#sudo mount --bind /parentroot/mnt/lineage/mer /srv/mer
sudo mount --bind /parentroot/mnt/lineage /mnt/lineage

#sudo mount /srv/mer -o remount,dev
sudo mount /home/vlad/hadk -o remount,dev
```

`sfossdk`

2. Android/HABUILD
   ===

`ubu-chroot -r $PLATFORM_SDK_ROOT/sdks/ubuntu/`
`cd ~/hadk`
`. build/envsetup.sh`
`ALLOW_MISSING_DEPENDENCIES=true TEMPORARY_DISABLE_PATH_RESTRICTIONS=true breakfast lineage_tucana-userdebug`
