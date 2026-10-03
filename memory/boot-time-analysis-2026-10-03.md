# Boot time analysis — tucana (2026-10-03)

Goal: shorten time from power-on to the GUI (PIN entry screen).
Logs: `logs/journal{1..6}.txt`, `logs/logcat{1..6}.txt` (logcat5 also contains run 4's buffer, filter on 21:33+).

## How we measure

All times are seconds after the kernel's `Booting Linux on physical CPU` line (journal has 1 s
resolution, bootloader time not included — add ~8–9 s for "since power button").

| Milestone | grep in journal |
|---|---|
| Wizard done / encryption gate | `Reached target Late Mount Post` |
| Bluetooth ready (gates the session) | `Reached target Network.` |
| User session | `Started Autologin` |
| lipstick first frame | `QEglScreen` |
| sensorfw ready | `Hybris sensor manager initialized` |
| **PIN screen visible** | `QEglWindow` |
| Fully booted | `Started Indicate boot is done` |

hwcomposer ready: `Registered android.hardware.graphics.composer` in logcat.
Sensors HAL: `sensors_hal initialized, init_time` and `wait_for_mandatory_sensors` in logcat.
Tip: `journalctl -b -o short-monotonic` gives ms resolution.

## Results

| Milestone | Run 1 | Run 2 | Run 4 | **Run 6** |
|---|---|---|---|---|
| Late Mount Post | +10 | +9 | +5 | +5 |
| network.target / autologin | +6 / +10 | +9 / +9 | +10 / +10 | +9 / +9 |
| lipstick first frame | +13 | +12 | +13 | +13 |
| sensorfw ready | +19 | +19 | +19 | **+11** |
| **PIN screen (QEglWindow)** | +22 | +22 | +21 | **+17** |
| Boot done | +27 | +28 | +27 | **+22** |

(Run 3 hit a 60 s bluebinder hang, see below.)

## Findings and status

### Done

1. **Encryption wizard `sleep 5`** (`hybris/mw/sailfish-device-encryption-community`, commit 39d4318).
   The sleep was a crude wait for hwcomposer before the wizard draws. Replaced by
   `/usr/bin/droid/wait_for_hwcomposer`; wizard no longer runs on normal boots
   (only when `/etc/sailfish-device-encryption-community/config.ini` is missing).
2. **Disabled Android services** in `disabled_services_device.rc` (wfd*, incidentd, iorapd, idmap2d,
   statsd, adb_root, logd-auditctl, qti-testscripts, leds-sh, minidump64, iop-hal-2-0).
   Small CPU gain, not measurable at 1 s resolution. Lines 32+ were re-enabled for a bisect —
   restore the full list if wanted.
   **Keep `citsensor-hal-1-1` enabled**: the hwcomposer uses it (`libsensor-C2SNotifier: get citsensorservice!`).
3. **`/dev/ttyHS0` permission race** (run 3: BT HAL `Permission denied`, bluebinder hung 60 s).
   Permissions come only from `/vendor/etc/init/hw/init.qcom.rc` `on boot` (chown line 126),
   which runs *after* `/init.rc`'s `on boot` → `class_start hal`. No ueventd rule exists, and
   `makeudev` doesn't see the prebuilt `/vendor/ueventd.rc`. Fixed with a udev rule:
   `ENV{DEVNAME}=="/dev/ttyHS0", OWNER="bluetooth", GROUP="net_bt", MODE="0660"`.
   `Readme/scripts/rc2udev.sh` generates such rules for all init chown/chmod of /dev nodes
   (run on device; output not reviewed yet).
4. **bluebinder hangs on HAL init failure** (still in upstream 1.0.20): the failure callback never
   quits the main loop, so no READY=1 until `TimeoutStartSec=60`. Patched in
   `hybris/mw/bluebinder/bluebinder.c` (`g_main_loop_quit(proxy->loop);` in the `!is_success`
   branch). **Not built/tested yet**; worth an upstream PR to mer-hybris/bluebinder.
5. **Sensors HAL waited ~8 s per boot for stale "mandatory" sensors.** `/persist/sensors/sensors_list.txt`
   (sensors@1.0-service) and `cit_sensors_list.txt` (citsensorservice) list `har` and
   `oem9_raiseCAM` (MIUI-era); the SLPI registry (`/persist/sensors/registry/registry/`) has no such
   sensors. sensorfwd blocks on the HAL and lipstick's window waits for sensorfwd.
   Removed the entries manually on this device → sensorfw +19 → +11, PIN screen +22 → +17.

### Open

- **Persist cleanup for other users** — see next section.
- **Bluetooth gates the user session (~4 s)**: `bluetooth.service` (bluez5, not built by us) has
  `Before=network.target`, and `systemd-user-sessions` waits on `network.target`; bluebinder waits for
  the BT HAL + firmware download (~+7 → +9). Only fix without rebuilding bluez5 is a full copy of
  the unit in `/etc/systemd/system/` without that line (loses package updates). Optional:
  `sleep 1` → `sleep 0.2` in `bluebinder_wait.sh`.
- **lipstick's own startup (~8 s)**: autologin +9 → first frame +13 → window +17. Not analysed yet.
- **hwcomposer stop/start race** in the wizard and `systemd-ask-password-gui` units: if `start` arrives
  before the old process is reaped, Android init delays the restart until 5 s after the previous start
  (run 2 lost ~3 s). Only matters on first boot / encrypted devices. Race-free version:
  `ExecStartPre=-/bin/sh -c '/system/bin/stop vendor.hwcomposer-2-3; while [ "$(/system/bin/getprop init.svc.vendor.hwcomposer-2-3)" != stopped ]; do sleep 0.1; done; /system/bin/start vendor.hwcomposer-2-3'`
- `systemd-ask-password-gui.service` is `Type=notify` but the app runs as `ExecStartPre` and the main
  process is `/bin/echo` → probably fails with `protocol` on encrypted devices. Should be
  `Type=oneshot` + `RemainAfterExit=yes`. (It is path-activated via `/run/systemd/ask-password`, so it
  costs nothing on unencrypted boots.)
- **Audio clock log burst** (`afe_set_lpass_clk_cfg`, ~440–1240 kernel lines in 1–2 s at audio HAL
  start, only 10 in run 1). Not caused by the disabled services. Likely the ultrasound/audio HAL
  startup; low priority.
- vold is re-enabled (`disabled_services.rc`); costs ~20 ms, not on the critical path. Why lipstick
  needed it was never confirmed.
- `ICameraProvider/legacy/0` is requested ~11× by hwservicemanager during boot — some client polls it.
- `hybris/mw-4.0.1` is stale and can be removed.

## Idea: fix persist sensor lists for all devices

Every tucana coming from MIUI probably has the same stale entries, and `/persist` isn't shipped by
droid-configs. Proposal: a oneshot unit in droid-configs that strips the known-stale entries before
droid-hal-init starts the sensors HAL. Only touches these two text files (persist also holds factory
calibration — never touch anything else). Rewriting in place with `cat >` keeps owner/mode/SELinux label.

Before adding: confirm the HAL doesn't put the lines back across reboots, and check the real
mount path with `mount | grep persist` (`/persist` vs `/mnt/vendor/persist`).

`sparse/usr/bin/droid/fix-persist-sensors-lists.sh`:

```sh
#!/bin/sh
# MIUI-era mandatory sensor lists name sensors the SLPI registry never provides;
# the sensors HAL then waits ~8 s per list on every boot.
STALE='har|oem9_raiseCAM'

for f in /persist/sensors/sensors_list.txt /persist/sensors/cit_sensors_list.txt; do
    [ -f "$f" ] || continue
    grep -qxE "$STALE" "$f" || continue
    grep -vxE "$STALE" "$f" > "$f.new" && cat "$f.new" > "$f"
    rm -f "$f.new"
done
```

`sparse/usr/lib/systemd/system/fix-persist-sensors-lists.service`:

```ini
[Unit]
Description=Drop stale entries from sensors HAL mandatory lists
DefaultDependencies=no
RequiresMountsFor=/persist
Before=droid-hal-init.service

[Service]
Type=oneshot
ExecStart=/usr/bin/droid/fix-persist-sensors-lists.sh

[Install]
WantedBy=droid-hal-init.service
```

A more generic version could compare each list entry against the sensors the HAL actually
discovers, but the explicit list is simpler and safe.

## Useful device-side commands

```sh
systemd-analyze critical-chain systemd-user-sessions.service
systemctl show -p After,Before <unit>
grep -rn <devnode> /vendor/ueventd.rc /vendor/etc/init /lib/udev/rules.d
grep -nx har /persist/sensors/*.txt
```
