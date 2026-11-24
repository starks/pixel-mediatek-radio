# Pixel MediaTek Radio

An MIT-licensed, app-independent reference for reading and changing LTE and 5G NR band masks on rooted Pixel phones with a MediaTek modem.

## ATCI socket

On the tested Pixel, the modem accepts standard MediaTek band commands through the Unix socket `/dev/socket/rild-atci`. The client connects, sends a four-byte big-endian length and a CR-terminated AT command, and reads the text reply.

Verified on a Pixel 11 Pro XL (`kodiak`), Android 17 build `DP11.261030.003`, with root and logical SIM slot 1. The socket targets slot 1 when `persist.vendor.service.atci.sim` is unset or zero. Other Pixel 11 models, firmware builds, slot 2, and simultaneous dual-SIM locks remain unverified.

### Try it

Use [pixel-atci.sh](pixel-atci.sh) from Android's root shell:

```sh
adb push pixel-atci.sh /data/local/tmp/pixel-atci.sh
adb shell "su -c 'sh /data/local/tmp/pixel-atci.sh read lte'"
adb shell "su -c 'sh /data/local/tmp/pixel-atci.sh read nr'"
adb shell "su -c 'sh /data/local/tmp/pixel-atci.sh capabilities nr'"
```

`read` returns the current mask fields. `capabilities` returns supported fields. On the device, save the full `read` output before changing masks. Pass the desired fields as one quoted argument to `pixel-atci.sh apply lte|nr MASKS`, and read back again to verify the result. To restore, apply the saved fields and check that the complete readback matches, including both NR masks when present. The modem can change cellular service when applying masks.

The ATCI path was tested by excluding LTE B29, locking NR to n66, and restoring the starting masks. Independent modem readback confirmed n66 in both NR masks and exact restoration. The [protocol reference](PROTOCOL.md#atci-socket) describes the field formats and what the modem acknowledges.

## Vendor Binder reference

[pixel-radio.sh](pixel-radio.sh) implements the earlier vendor Binder method for the verified Pixel 11 Pro XL firmware. It reads masks through temporary tracefs probes, supports independent NR mask edits, and saves restore points on the device. See the [Binder protocol and usage](PROTOCOL.md#vendor-binder-reference).

## License

The shell clients and protocol notes are original standalone implementations available under the [MIT License](LICENSE).
