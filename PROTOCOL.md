# Radio protocol reference

## Transport

This profile uses the MediaTek radio vendor AIDL service:

`vendor.mediatek.hardware.mtkradioex.network.IMtkRadioExNetwork/slot1`

Stable AIDL `getInterfaceVersion` returned 1. The table lists device-verified request forms for this build. Requests are one-way. A successful Binder submission does not establish modem success.

| Operation | AIDL method | Transaction | Arguments in order |
| --- | --- | ---: | --- |
| Read masks | `getAllBandMode` | 11 | `serial: int, clientId: int` |
| Edit one LTE band | `setLteBandEnableStatus` | 49 | `serial: int, band: int, enabled: bool, clientId: int` |
| Edit NR bands | `setNrBandMode` | 55 | `serial: int, addA: int[], removeA: int[], addB: int[], removeB: int[], clientId: int` |

Use `clientId = 0` for the verified vendor path. The Android `service call` CLI writes the Boolean as an i32 (0 or 1) and writes an int array as its i32 length followed by the elements. A native Binder client should use the generated AIDL types or the equivalent correctly typed parcel fields.

## Readback on this firmware

The modem responds to `getAllBandMode`. The daemon then delivers the payload through the MediaTek response callback. On the tested phone that callback was null when queried from an independent root client. The registration method writes both the response and indication callback slots, so this reference leaves callback registration alone.

The runnable profile creates an isolated tracefs instance and captures only the parsed mask words in the existing radio daemon. A client that already has a supported way to obtain those values can use that readback mechanism with the same mask operations and verification logic.

| Mask | MIPC field | Words | ELF file offset in `libmtkmipc-ril.so` | Register at probe |
| --- | ---: | ---: | ---: | --- |
| LTE | `0x102` | 8 | `0x451c88` | `x0` |
| NR A | `0x103` | 32 | `0x451cf4` | `x21` |
| NR B | `0x104` with firmware fallback to A | 32 | `0x451f8c` | `x8` |

Band N maps to bit `(N - 1) % 32` in word `floor((N - 1) / 32)`. This profile treats the NR banks independently. Their SA/NSA assignment has not been verified.

Verified SHA-256 values:

- `/vendor/lib64/libmtkmipc-ril.so` = `1600b8d2b3f7878e96b65ee9adccb3637841b9e96f58a9b6730b1c31ef48472f`
- `/vendor/lib64/vendor.mediatek.hardware.mtkradioex.network-V1-ndk.so` = `cdb02c674a5a55955709e080c53f92be50e0695748bbb4f9c2182cc902851183`

## Apply and restore

1. Read the current masks twice and require matching snapshots. Commit a durable restore point before the first write.
2. Intersect the requested bands with each baseline mask. Require a nonempty result for each applicable mask. Compute separate additions and removals from the current and target values.
3. On LTE, submit one change at a time and confirm each against modem readback before submitting the next. On this build some LTE writes take about five seconds. On NR, send the four delta arrays together.
4. Confirm the resulting masks. Report serving-band attachment independently using Android's primary physical channel report.
5. To restore, compute the delta from the current masks back to the saved baseline. Clear the restore point after every original word matches. Retain it if verification fails.

The reference implementation serializes its own requests and cooperates with the paired Bunnylock build via a shared file lock. Third-party radio clients can still change the modem independently.
