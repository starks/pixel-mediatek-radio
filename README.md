# Pixel MediaTek Radio

An app-independent reference for LTE and 5G NR band locking through the MediaTek radio vendor service on a rooted Pixel. It includes a runnable Android shell client and [protocol notes](PROTOCOL.md) for modem-tool developers.

For integration into another app, see the [MIT-licensed NSG reference](nsg-reference/README.md).

## Compatibility

Verified on one Pixel 11 Pro XL (`kodiak`), Android 17 build `DP11.261030.003`, baseband `a900a-QPR_260921-260923-M-16421473`, using slot 1 as the default data line (subscription ID 1). The helper gates access on the device codename, both vendor library hashes, the Binder interface version, and the tested default data subscription ID. Other firmware builds need their own validation.

## Run on a rooted device

Copy [pixel-radio.sh](pixel-radio.sh) to the device and start with readback. Each command registers temporary trace probes and removes them on exit.

```sh
adb push pixel-radio.sh /data/local/tmp/pixel-radio.sh
adb shell "su -c 'sh /data/local/tmp/pixel-radio.sh read lte'"
adb shell "su -c 'sh /data/local/tmp/pixel-radio.sh read nr'"
```

The first successful lock saves the original mask for that radio technology. Later locks retain that restore point. Use numeric band IDs and keep the device connected over USB during testing. A lock can interrupt cellular service, and the LTE setter can take several seconds per changed band.

```sh
adb shell "su -c 'sh /data/local/tmp/pixel-radio.sh lock lte 2'"
adb shell "su -c 'sh /data/local/tmp/pixel-radio.sh restore lte'"
adb shell "su -c 'sh /data/local/tmp/pixel-radio.sh lock nr 41 66'"
adb shell "su -c 'sh /data/local/tmp/pixel-radio.sh restore nr'"
```

- `BASELINE_A/B` and `CURRENT_A/B` show enabled band IDs for each modem mask. The baseline reflects the configuration before this tool first applied a lock, which can already be narrower than the modem's hardware capabilities.
- `ATTACHED N` means Android reported the selected band as the primary serving band for that radio technology. `MASK_ONLY` means mask readback matched the selection and primary attachment was unobserved. The helper leaves the current LTE/NR network preference alone.
- `RESTORED` means every original mask word matched. `RESTORE_POINT_PRESENT` means a rollback snapshot is available. The CLI shares its file lock and saved masks with the tested Bunnylock backend so either can restore them.
- A successful restriction stays after the command exits. Reboot persistence is unverified. If a process dies before cleanup, the saved restore point remains available as long as the tested firmware and subscription configuration are still active.

## Verified results

The shared implementation was tested on the device above. LTE B2-only produced primary LTE B2 in all three observations under temporary LTE-only network mode. NR n66-only produced primary NR n66 on NR-ARFCN 430090, and a separate n41+n66 test verified multi-band readback. Both LTE and NR restore paths matched their original masks word for word. The standalone packaging is smoke-tested with read-only commands.

The implementation was extracted from the Pixel MediaTek Radio backend developed in a local checkout of [Bunnylock](https://github.com/btsearch/bunnylock). See [LICENSE](LICENSE) for the source distribution terms.
