# Screenless band prototype

This repository contains the first iPhone app iteration for a screenless
fitness band. It stores daily steps, vendor calorie estimates, and sleep
sessions on the phone. Bluetooth sync is pending the H7 sample.

## Feasibility decision

**Proceed to a one-unit hardware proof of concept. Do not commit to a production
order yet.** The [Veepoo iOS SDK](https://github.com/HBandSDK/iOS_Ble_SDK)
documents BLE scanning, connection, historical data sync, steps, calories, and
sleep. Its current package contains demo code and precompiled frameworks. The
[Alibaba H7 listing](https://www.alibaba.com/product-detail/Screenless-Smart-Bracelet-ECG-PPG-HRV_1601721998039.html)
advertises an SDK, accelerometer, heart-rate monitor, step and sleep tracking,
but calls its companion app **G band**. On 2026-09-28, the supplier pointed us
to `github.com/HBandSDK` and said its SDK can retrieve device data through our
own app without the supplier app or cloud. This is encouraging supplier
confirmation, not a successful integration test for the exact H7 firmware.
The supplier quoted **$30.30 DDP to the USA for one sample** ($15.30 device +
$15 shipping). A sample is still required to verify compatibility and offline
operation.

The three product metrics have different confidence levels:

| Metric | First version | Validation needed |
| --- | --- | --- |
| Steps | Display device count and daily trend | Compare with manual counts during walking, running, and ordinary daily use |
| Sleep | Display sleep window and estimated duration | Compare several nights with a reference; treat stages as estimates |
| Calories | Display the device's value labeled **estimate** | Determine active vs total definition, then compare with reference data; do not derive it from steps alone |

## Build order

1. Obtain one H7 sample, its exact firmware/version, and confirmation of the
   specific HBandSDK repository and commercial SDK terms.
2. On a physical iPhone, prove scan → connect → authenticate → sync → read a
   full day of steps and one night of sleep while offline.
3. Inspect SDK network behavior and license; confirm the app can work without
   an account, vendor app, vendor servers, or mandatory telemetry.
4. Connect the resulting adapter to the app and validate steps, sleep duration,
   and energy estimates with real users and references.
5. Only after those gates, quote landed cost, returns, support, certifications,
   and the economics of a $60–$70 one-time price.

## Current implementation

`BandCore` provides an explicit daily record, sleep sessions, a mapper for the
documented Veepoo `Step`/`Cal` dictionary, a device-sync interface, a local
JSON store, and an on-device scoring engine (`ScoringEngine`): a 0-100
readiness score from sleep duration, efficiency, and consistency against
your own baseline, plus a 0-100 day activity load score from steps
and active minutes. Activity sessions (tagged workouts, auto-detected
bouts) are stored locally too. Heart-rate inputs are reserved in the
model and get wired in once HR sync is proven on hardware. The iPhone app displays those three metrics and can load a clearly-marked deterministic 7-day mock week through the
same adapter path as the real sync while hardware is in transit. It does not claim that the
preview numbers came from a device. The store excludes its file from device
backups and applies iOS file protection. The app has no network code. This is
not yet a finished privacy claim: the Bluetooth SDK, app dependencies, crash
reporting, and distribution build must also be audited.

Open [BandApp.xcodeproj](BandApp.xcodeproj) in Xcode, select an iPhone simulator,
and run the `BandApp` scheme. Tap **Preview dashboard with sample data** to see
the initial layout. Run `swift test` to check the data layer.

## Source references

- [HBandSDK iOS_Ble_SDK repository](https://github.com/HBandSDK/iOS_Ble_SDK) — the supplier’s SDK repo: precompiled framework, API documentation, and demo app.
- [Veepoo iOS API documentation](https://github.com/HBandSDK/iOS_Ble_SDK/blob/master/iOS_sdk_source/doc/VeepooSDK%20iOS%20Api_en.md)
- [Veepoo iOS framework headers](https://github.com/HBandSDK/iOS_Ble_SDK/tree/master/iOS_sdk_source/Framework)

## Third-party code

Everything under `Vendor/` is third-party and NOT covered by the MIT license
above: `VeepooBleSDK.framework` is distributed by the band vendor via the
public [HBandSDK](https://github.com/HBandSDK/iOS_Ble_SDK) repository (see its
terms there), and `FMDB` / `AFNetworking` are vendored sources under their own
licenses. Our code (`Sources/`, `BandApp/`, `Tests/`, `docs/`) is MIT.
- [Alibaba H7 listing](https://www.alibaba.com/product-detail/Screenless-Smart-Bracelet-ECG-PPG-HRV_1601721998039.html)
