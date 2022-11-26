# Sailfish on tucana

# Installing
Installing requires unlocking your device and installing [TWRP](https://twrp.me/xiaomi/xiaomiminote10.html).
Your device will probably be out of warranty.

You need MIUI Android 10 vendor partition.
You can use [tucana_global_images_V12.0.3.0.QFDMIXM_20201026.0000.00_10.0_global](https://xiaomifirmwareupdater.com/miui/tucana/stable/V12.0.3.0.QFDMIXM/) or [xiaomi.eu_multi_MINote10_MICC9Pro_20.3.26_v11-10.zip](https://androidfilehost.com/?fid=4349826312261755292) (recommended).

Both of the Xiaomi firmwares above will replace TWRP - but the latter will allow you to replace it back without reverting it at each boot.

Next you can install this Lineage 17.1 build: https://forum.xda-developers.com/t/deprecated-rom-10-unofficial-tucana-lineageos17-1.4196085/
(or use mine, https://1drv.ms/u/s!Alh0arVfv0RwirZ7aGrClFPS1kXTqw?e=7JhQVY - the only difference is that mine uses the OSS kernel, but we will replace this next).

## Pre-release
https://github.com/sailfishos-on-tucana/Readme/releases/tag/4.4.0.72-camfix
Installed by pushing the zip to the device and using the TWRP install zip option.


## Beta3
<details>
  <summary>Beta version 2021-12-09</summary>
https://github.com/sailfishos-on-tucana/Readme/releases/tag/4.3.0.15-beta-3
Installed by pushing the zip to the device and using the TWRP install zip option.
</details>

## Beta2
<details>
  <summary>Beta version 2021-10-08</summary>
This [beta version](https://github.com/sailfishos-on-tucana/Readme/releases/tag/4.2.0.21) is installed by pushing the zip to the device and using the TWRP install zip option.
</details>

## Prerelease-0
<details>
<summary>Prerelease version 2021-08-10</summary>

The [prerelease version](https://github.com/sailfishos-on-tucana/Readme/releases/tag/4.1.0.24-prerelease) (that is, you get all the [issues](https://github.com/sailfishos-on-tucana/Readme/issues)) is installed by pushing the zip to the device and using the TWRP install zip option.
</details>

## Alpha
<details>
  <summary>Alpha version 2021-06-06</summary>
You need a MIUI Android 10 vendor partition, I used [tucana_global_images_V12.0.3.0.QFDMIXM_20201026.0000.00_10.0_global](https://xiaomifirmwareupdater.com/miui/tucana/stable/V12.0.3.0.QFDMIXM/) - probably others will work.
Boot into it at least once to verifiy the downgrade worker correctly.

This is mainly for the vendor partition but any other device calibrations that could be done.

Next you can install this Lineage 17.1 build: https://forum.xda-developers.com/t/deprecated-rom-10-unofficial-tucana-lineageos17-1.4196085/
(or use mine, https://1drv.ms/u/s!Alh0arVfv0RwirZ7aGrClFPS1kXTqw?e=7JhQVY - the only difference is that mine uses the OSS kernel, but we will replace this next).

Next install the [alpha release](https://github.com/sailfishos-on-tucana/Readme/releases/tag/4.0.1.48-alpha) (that is, you get all the [issues](https://github.com/sailfishos-on-tucana/Readme/issues): 
You download the boot image and the bz2 file, install the img with twrp on the boot partition and for the bz2 do:
```
#!/bin/bash -x
RELEASE=4.0.1.48
EXTRANAME=${EXTRANAME:=-alpha}
echo publishing $RELEASE$EXTRANAME
sudo bunzip2 -vf sfe-tucana-$RELEASE$EXTRANAME.tar.bz2
adb shell mkdir -p /data/.stowaways/sailfishos
adb push sfe-tucana-$RELEASE$EXTRANAME.tar /sdcard/
adb shell tar --numeric-owner -xf /sdcard/sfe-tucana-$RELEASE$EXTRANAME.tar -C /data/.stowaways/sailfishos
```
</details>
