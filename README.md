# AdwellSDK for iOS

[Adwell](https://runadwell.com) joins Apple Ads keywords to subscription
revenue. This package gives each install a stable id and sends Apple's
attribution token to Adwell once, so revenue can be traced back to the
keyword that brought the user.

- No dependencies, no swizzling, no work on the main thread, nothing throws.
- No IDFA and no tracking prompt: Apple's AdServices attribution needs neither.
- iOS 14+ (attribution tokens from iOS 14.3).

## Install

Swift Package Manager: add `https://github.com/runadwell/adwell-ios` from
`0.1.0`, product `AdwellSDK`. Flutter apps use the
[`adwell_sdk`](https://pub.dev/packages/adwell_sdk) plugin instead.

## Use

```swift
import AdwellSDK

// At launch:
Adwell.configure(apiKey: "pk_live_…")

// On every launch, after your billing SDK is configured, give it the id. RevenueCat:
Purchases.shared.attribution.setAttributes(["adwell_install_id": Adwell.installID])

// StoreKit 2 without a billing SDK:
try await product.purchase(options: [.appAccountToken(Adwell.appAccountToken)])
```

The publishable key (`pk_live_…`) comes from Adwell → Setup → Keys. It can
only send installs for your app; it cannot read anything.

Options: `AdwellOptions(environment: .staging, logLevel: .debug)` points at
Adwell's staging API (`pk_test_…` keys) and logs to the console under
`com.runadwell.sdk`.

## Setup errors

In debug builds the SDK prints setup problems to the console (Xcode, or
`flutter run`), each with what to do about it:

```
[Adwell] Error: pk_test_ keys only work with the staging environment. Use your pk_live_ key, or pass AdwellOptions(environment: .staging). Adwell is not sending anything.
```

- Checked at `configure`, before anything is sent: no key, spaces or a line
  break around it, not a `pk_live_`/`pk_test_` key, a truncated key, a key
  for the other environment.
- Reported from Adwell's answer: an unknown or revoked key, a key for
  another app (names your bundle id), any other rejection with Adwell's
  reason.
- When it works: `[Adwell] Connected: install <id> sent to api.runadwell.com.`
  (once per install).

Keys are shown cut short (`pk_live_Ab3_…`). Release builds print nothing
unless you pass `logLevel: .debug`. Network failures are not errors: the SDK
retries quietly.

## What it sends

Once per install, to `https://api.runadwell.com/v1/ingest/install`: the
install id, bundle id, app and OS version, locale, App Store country, whether
this is a reinstall on the same device, Apple's attribution token (or why
there is none), and the SDK version. Nothing else, ever. If the request fails
it retries in the background (15 s, 1 min, 5 min, then every 15 min, and
when the app returns to the foreground) until Adwell acknowledges it.

The id lives in the Keychain (this device only) and UserDefaults, so it
survives app updates and, on the same device, reinstalls.

## Privacy

The package ships `PrivacyInfo.xcprivacy`: no tracking, no tracking domains,
Device ID collected for analytics and not linked to the user, UserDefaults
accessed for reason `CA92.1`. In App Store Connect's privacy labels, declare
"Identifiers → Device ID", not linked to the user, not used for tracking.

## License

MIT
