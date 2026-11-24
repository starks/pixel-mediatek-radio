# NSG integration reference

This directory contains an independently written Java mask codec, observed Binder interface facts, and reproducible mask vectors. Everything under this directory is available under [MIT](LICENSE).

## Integrate

1. Feed the LTE words or each of the two NR word arrays into `BandMask.fromWords`.
2. Save the original arrays before changing the modem. Build a target with `baseline.select(bandIds)`, then obtain the required changes with `current.deltaTo(target)`. Restore with `current.deltaTo(baseline)`.
3. Send the delta through the native radio interface and compare the modem's returned words with the target. Use the serving cell independently to determine whether the requested band became primary.

The Java code only handles masks. The host app supplies its privileged Binder transport, readback, durable restore storage, and device checks.

## Verified Binder profile

Device tested was a rooted Pixel 11 Pro XL (`kodiak`) with Android build `DP11.261030.003` and baseband `a900a-QPR_260921-260923-M-16421473`. The slot 1 service name was `vendor.mediatek.hardware.mtkradioex.network.IMtkRadioExNetwork/slot1`, interface version 1. The final argument in the table is client ID 0.

| Transaction | Method | Parameters in order |
| --- | --- | --- |
| 11 | `getAllBandMode` | serial, client ID |
| 49 | `setLteBandEnableStatus` | serial, numeric LTE band, enable boolean, client ID |
| 55 | `setNrBandMode` | serial, NR A additions, NR A removals, NR B additions, NR B removals, client ID |

The masks contain 8 LTE words and two arrays of 32 NR words. Band N uses zero-based word index `(N - 1) / 32` and bit index `(N - 1) % 32`. The tested firmware applies LTE edits individually. Wait for each edit to be reflected in readback before sending the next.

The Binder requests are asynchronous. The modem supplied the readback in the vendor daemon even when the independent client had no response callback. For the tested library, the LTE value pointer was in x0 at file offset 0x451c88, NR A in x21 at 0x451cf4, and NR B in x8 at 0x451f8c. These offsets apply to `libmtkmipc-ril.so` with SHA-256 `1600b8d2b3f7878e96b65ee9adccb3637841b9e96f58a9b6730b1c31ef48472f`. Use the host's existing readback path if it exposes the same three masks. The codec has no dependency on tracing.

## Run the vectors

From this directory, use a JDK to compile the source and exercise the observed B2, n66, and n41 plus n66 selections and their inverse deltas.

```sh
mkdir build
javac -d build src/pixelradio/BandMask.java examples/VerifiedVectors.java
java -cp build VerifiedVectors
```
