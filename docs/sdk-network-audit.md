# Veepoo SDK network audit

Date: 2026-09-28. SDK: VeepooBleSDK.framework v2.0.43.15 (static, arm64 slice analyzed).
Method: `strings` over the full binary, per-object-file attribution after
`lipo -thin arm64` + `ar x`, selector tables, public headers, and the demo app
source. No runtime traffic was captured yet — that is the follow-up step.

## Destinations found (complete list)

The entire framework references exactly two network hosts:

| Host | Scheme | Used by | Purpose |
| --- | --- | --- | --- |
| `www.vphband.com:505` | plain HTTP, custom port | `VPCheckDeviceVersion.o`, `VPMarketDialManager.o` | Firmware version check; watch-face ("market dial") downloads |
| `mxcaring.wherecom.com` | HTTPS | `VPCheckDeviceVersion.o` | "Upload SDK message" (`POST api/system/addsdkuserinfo`) |

No other URLs, IPs, or hosts exist anywhere in the binary.

## What is sent

Firmware version check (`VPCheckDeviceVersion`):

- `GET http://www.vphband.com:505/api/Version/GetVersionForSport?type=ios&DeviceType=<band model>&testVersion=<firmware>`
- "Upload SDK message": band model number, firmware version, band Bluetooth
  MAC address, SDK version, app version, phone version →
  `https://mxcaring.wherecom.com/` + `api/system/addsdkuserinfo`

This is device-identifying metadata. **No health data** (steps, sleep, heart
rate, calories) appears in any network code path. The health-data flow in our
app is BLE → SDK's local SQLite database → our app, and never touches the
network.

Watch-face market (`VPMarketDialManager`): downloads dial listings and `.bin`
dial files from `www.vphband.com:505`. This code is **unreachable in our app**
— no other object file references it and our sync flow never calls it.

## When it fires

`VPCheckDeviceVersion` has no public header and is never called by the demo
app, yet `VPBleCentralManage.o` (the central manager our `VeepooBandSyncClient`
uses for scan/connect) directly invokes all three of its entry points
(`shareCheckVersion`, `veepooSDKCheckVersion:…`, `veepooSDKUploadSDKMessage…`).
There is no API to disable it. Conclusion: **assume the version check and the
SDK-info upload can fire during our normal scan/connect flow** until a live
capture proves otherwise.

## Implications

- The claim "your health data never leaves your phone" holds: health metrics
  stay in the on-device SQLite database.
- The claim "the app makes no network calls at all" would be **false**: the
  SDK can send the band's MAC address, model, and firmware version to vendor
  servers — one of them over unencrypted HTTP.
- For a privacy-positioned product this needs a supplier answer: can the
  version check / SDK-info upload be disabled, or is there a no-phone-home
  SDK flavor? (See the commercial-terms question for the supplier.)

## Follow-up

On hardware day (~Oct 7), run the sync flow with a proxy (Proxyman/Charles on
the Mac, iPhone traffic routed through it) and record exactly which of these
endpoints fire during scan → connect → sync. Static analysis says what *can*
happen; the capture says what *does* happen.
