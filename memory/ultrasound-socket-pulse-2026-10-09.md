# Ultrasound proximity via audio_hw_socket in PulseAudio: tucana (2026-10-09)

Goal: a working Elliptic ultrasound proximity sensor without the old audio-hal-2-0 + audioserver
workaround, which intermittently lost call audio. See https://github.com/sailfishos-on-tucana/Readme/issues/9.
Logs: `logs/logcat{4,5,6}.txt` (baseline), `logs/logcat10.txt` + `logs/journal10.txt` (first try, startup crash).

## How ultrasound proximity works (vendor V12.0.3.0.QFDMIXM)

1. The sensors multihal (`vendor/etc/sensors/hals.conf`) loads `sensors.elliptic.so`. On ACTIVATE it calls
   `libnotifyaudiohal.so`, which calls `libultrasound.so`.
2. `libultrasound` connects to the seqpacket socket **`/dev/socket/audio_hw_socket`** and sends
   `ultrasound-proximity=1` (and `=0` on deactivate). `audioshell_service` is another client of the same socket.
3. The server is the vendor **`audio.primary.sm6150.so`**: a listener thread started in `adev_open`, using
   `android_get_control_socket("audio_hw_socket")`. Android init creates that socket only for
   `vendor.audio-hal-2-0` (`socket audio_hw_socket seqpacket 0666 system system` in `vendor/etc/init/hw/init.qcom.rc`).
4. The HAL then sets the Elliptic mixer controls and starts the ultrasound pseudo port in the DSP. Kernel log:
   `[ELUS] ... custom_setting`, `afe_start_pseudo_port: port_id = 0x8001`.

It is a plain Unix socket, not binder: audioserver/AudioFlinger are not involved, and neither are the
audiosystem-passthrough modes.

## Why the old workaround was flaky

audioserver only served to make `android.hardware.audio@2.0-service` open (load) the HAL; the HAL service
owned the socket. That created **two copies of the same HAL** on one sound card: one in PulseAudio
(module-droid-card, jb2q) doing calls, one in the HAL service doing ultrasound. The HAL's ultrasound/voice
coordination (`ultrasound_suspend_usecase`, shared backend, ...) only works within one copy, and each copy
resets mixer state when it starts. Start order only made the failure rarer.

## What we did

Keep audio-hal-2-0 and audioserver disabled. Give the HAL **inside PulseAudio** the socket, the way init would.

Package **`audio-hw-socket`** (`hybris/mw/audio-hw-socket`, noarch), required by
`patterns-sailfish-device-adaptation-tucana`:

| File | Purpose |
|---|---|
| `/usr/lib/tmpfiles.d/audio-hw-socket.conf` | `d /dev/socket 1775 root audio -` so the user (group audio) can bind there; the sticky bit prevents deleting or replacing Android's sockets |
| `/usr/lib/systemd/user/audio-hw-socket.socket` (+ `sockets.target.wants`) | user systemd binds `/dev/socket/audio_hw_socket`, `FileDescriptorName=audio_hw_socket`, `Service=pulseaudio.service` |
| `/usr/lib/systemd/user/pulseaudio.service.d/50-audio-hw-socket.conf` | runs PulseAudio through the wrapper; hide/restore of the path (see below) |
| `/usr/libexec/pulseaudio-audio-hw-socket` | finds the fd by name in `LISTEN_FDNAMES`, exports `ANDROID_SOCKET_audio_hw_socket=<fd>`, then `exec "$@"` |

Facts this relies on:
- libcutils `android_get_control_socket()` (`system/core/libcutils/sockets_unix.cpp`) needs a valid fd in
  the env var **and** `getsockname()` == `/dev/socket/audio_hw_socket`. So the socket must really be bound
  there; a symlink or a different path won't work.
- The system systemd can't pass fds to a user service, so the user instance has to do the binding. Hence
  the `/dev/socket` permission change.
- PulseAudio's `main.c` closes all inherited fds except systemd `LISTEN_FDS` (and `PULSE_PASSED_FD`).
  Socket-activated fds survive.
- libhybris forwards `getenv` to glibc (`HOOK_DIRECT(getenv)`), so the bionic HAL sees the variable.
- systemd passes fds starting at 3, in `LISTEN_FDNAMES` order. With the stock user `pulseaudio.socket`
  inactive, the HAL gets fd 3.

### Startup crash and the hide/restore

First try (logcat10/journal10): mce turned proximity on at boot while PulseAudio was still starting. The
request waited on the socket, and the HAL accepted it from `adev_open`, before module-droid-card had opened
its outputs. **PulseAudio SIGSEGV'd** (rich-core `--signal=11 --name=pulseaudio`) twice, right after
`afe_start_pseudo_port`. Elliptic gave up after 3 retries. Restarting sensorfwd once PulseAudio was up
worked fine, which confirmed the race.

Fix: the path exists only while PulseAudio is ready.
- socket unit `ExecStartPost`: `mv audio_hw_socket .audio_hw_socket` right after binding.
- pulseaudio `ExecStartPost` (after `READY=1`, i.e. after default.pa is fully loaded): `mv` back.
- pulseaudio `ExecStopPost` (including crashes): hide again.

The rename keeps the inode, so PulseAudio's fd stays valid, and `getsockname()` still reports the original
path. Requests made while the path is hidden get ENOENT and are lost; proximity comes back on the next
activation (next call, or the display going off and on).

## mce note

droid-configs ships `/system/osso/dsm/proximity/on_demand=true` (`sparse-10/etc/mce/60-proximity-sensor.conf`),
but the device reported `Use ps on-demand: disabled`, most likely a value saved earlier in
`/var/lib/mce/builtin-gconf.values`. With on-demand off, sensorfw keeps proximity, and therefore the ultrasound
tone and mic capture, running whenever the display is on, which costs battery. `mcetool --set-ps-on-demand=enabled`
limits it to calls, alarms and the low-power display mode. Trade-off: the double-tap wakeup policy `proximity`
can no longer check proximity while the display is off.

## Debugging

Quick health check (as root, PulseAudio running):
```sh
P=$(pidof pulseaudio)
ls -ld /dev/socket                              # drwxrwxr-t root audio
ls -la /dev/socket | grep audio_hw              # only "audio_hw_socket" (srw-rw-rw-, defaultuser) while PA is up
tr '\0' '\n' < /proc/$P/environ | grep -E "LISTEN_FDNAMES|ANDROID_SOCKET"   # audio_hw_socket / =3
ls -l /proc/$P/fd/3                             # socket:[...]
grep audio_hw /proc/net/unix
```

What the logs say (`/system/bin/logcat -d | grep -iE "audio_hw_con|clientConnect|clientRequest|AudioNotify|ultrasound"`):

| Message | Meaning |
|---|---|
| `audio_hw_con: audio_hal_con_thread_start con->socket_server_fdr -1` | the HAL got no socket: env var missing, wrong fd, or wrong bind path. Check the environ/fd above |
| `audio_hw_con: add_client accept client connect N` | good, the HAL is accepting |
| `ultrasound: clientConnect: Error connect server socket ... No such file or directory` | path absent: PulseAudio not ready (expected briefly at boot), or the socket unit isn't running |
| `ultrasound: clientRequest read status error 32` / `Broken pipe` | the server died mid-request. Check `journalctl -b \| grep -E "rich-core\|pulseaudio.service"` for a PulseAudio SEGV |
| `Elliptic: AudioNotify: enable >> ultrasound-proximity=1` then `ultrasound_extn ... sensor_activated:1` | working |
| `mi_us_cal_load: Could not get MI_US_CAL ctl ... Mi_Ultrasound Calibration Data` | always present (the kernel lacks this Xiaomi control), harmless so far |

Re-trigger an activation without a call: `systemctl restart sensorfwd` (as root).
Crash backtrace: `rich-core-extract /var/cache/core-dumps/<pulseaudio...>.rcore.lzo /tmp/pa-core` and
`gdb /usr/bin/pulseaudio /tmp/pa-core/coredump -batch -ex bt`.

## Disabling

- Temporarily, without uninstalling (as defaultuser):
  ```sh
  systemctl --user mask audio-hw-socket.socket
  systemctl --user restart pulseaudio
  ```
  The wrapper then finds no fd and starts PulseAudio exactly as before. The `mv` steps are `-`-prefixed
  and fail silently. Undo with `systemctl --user unmask audio-hw-socket.socket` and restart PulseAudio again.
- Permanently: remove the `Requires: audio-hw-socket` line from the pattern, or `zypper rm audio-hw-socket`
  (needs `--force-resolution` while the pattern requires it). The tmpfiles mode on `/dev/socket` goes back to
  0755 root at the next boot.
- Do **not** go back to enabling `vendor.audio-hal-2-0`/audioserver: that brings back the two-HAL-copies problem.

## Open items

- A request made during PulseAudio startup is lost (by design); fine with mce on-demand, which activates only in calls.
- Persist mce on-demand=enabled, or find out what set it to disabled.
- `Mi_Ultrasound Calibration Data` mixer control is missing in the kernel; check whether proximity accuracy suffers.
- `hybris/mw/audio-hw-socket` is a fresh `git init` with nothing committed yet; it needs a commit and tag
  (mb2 sets the version from git) and an OBS package. The spec's `License:` is a placeholder (BSD-3-Clause).
