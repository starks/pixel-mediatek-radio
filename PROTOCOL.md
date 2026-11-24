# Radio protocol reference

## ATCI socket

Connect to `/dev/socket/rild-atci` as a Unix stream socket. Write an unsigned 32-bit big-endian payload length, then the ASCII command followed by CR. The length includes CR. The modem sends an unframed text reply whose final result is typically `OK` or `ERROR`. Use one outstanding command per connection, set a deadline, and verify writes with a readback.

| Action | LTE | NR |
| --- | --- | --- |
| Read current masks | `AT+EPBSE?` | `AT+EPBSEH?` |
| Read supported masks | `AT+EPBSE=?` | `AT+EPBSEH=?` |
| Apply masks | `AT+EPBSE=<fields>` | `AT+EPBSEH=<fields>` |

On the tested Pixel, LTE uses ten unsigned decimal words: GSM, UMTS, then eight LTE words. NR uses four quoted hexadecimal fields: GSM, UMTS, LTE, and NR. GSM and UMTS use one 32-bit word each. LTE uses three words in the hexadecimal form. The NR field is a series of eight-character 32-bit words in ascending band order. Bit 0 of the first LTE or NR word is band 1. Preserve the GSM, UMTS, and LTE fields when changing only NR.

The NR current-state reply can contain a fifth field for the second modem mask. The setter accepts four fields and updates both modem masks. A five-field setter returned `ERROR` on the test device. When the two masks were equal during the n66-only lock, the current-state AT reply had one NR field. Before a change, save the entire original reply, including the second mask if present. After a restore, compare the complete readback. The two masks' SA/NSA roles are unverified.

This transport was verified with root on logical SIM slot 1 on `DP11.261030.003`. The vendor daemon reads `persist.vendor.service.atci.sim` and uses zero by default. The client accepts that default and explicit zero. A slot 2 configuration remains unverified.

## Vendor Binder reference

The earlier [pixel-radio.sh](pixel-radio.sh) client implements the Binder path below. It rechecks the model, firmware hashes, service version, and default data subscription before use. Copy it to the phone and use `read lte|nr`, `lock lte|nr BAND [BAND ...]`, and `restore lte|nr` from a root shell. A successful lock persists after the process exits. Reboot persistence remains unverified.

### Transport

This profile uses the MediaTek radio vendor AIDL service:

`vendor.mediatek.hardware.mtkradioex.network.IMtkRadioExNetwork/slot1`

Stable AIDL `getInterfaceVersion` returned 1. The table lists device-verified request forms for this build. Requests are one-way. A successful Binder submission does not establish modem success.

| Operation | AIDL method | Transaction | Arguments in order |
| --- | --- | ---: | --- |
| Read masks | `getAllBandMode` | 11 | `serial: int, clientId: int` |
| Edit one LTE band | `setLteBandEnableStatus` | 49 | `serial: int, band: int, enabled: bool, clientId: int` |
| Edit NR bands | `setNrBandMode` | 55 | `serial: int, addA: int[], removeA: int[], addB: int[], removeB: int[], clientId: int` |

Use `clientId = 0` for the verified vendor path. The Android `service call` CLI writes the Boolean as an i32 (0 or 1) and writes an int array as its i32 length followed by the elements. A native Binder client should use the generated AIDL types or the equivalent correctly typed parcel fields.

### Readback on this firmware

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

### Apply and restore

1. Read the current masks twice and require matching snapshots. Commit a durable restore point before the first write.
2. Intersect the requested bands with each baseline mask. Require a nonempty result for each applicable mask. Compute separate additions and removals from the current and target values.
3. On LTE, submit one change at a time and confirm each against modem readback before submitting the next. On this build some LTE writes take about five seconds. On NR, send the four delta arrays together.
4. Confirm the resulting masks. Report serving-band attachment independently using Android's primary physical channel report.
5. To restore, compute the delta from the current masks back to the saved baseline. Clear the restore point after every original word matches. Retain it if verification fails.

The reference implementation serializes its requests with a file lock. Other radio clients can still change the modem independently.
