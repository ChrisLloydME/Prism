# Prism Native for macOS

Open `PrismNative.xcodeproj` in Xcode and select the `PrismNative` scheme.

The native app deliberately uses the bundle identifier `com.lloydME.Prism` and
the display name `Prism`. Display name is not a persistence key: the production
Application Support root is exactly
`~/Library/Application Support/com.lloydME.Prism`, with matching bundle-scoped
cache, log, saved-state, preferences, and any later-authorized Keychain names.
It never falls back to a generic `Prism` or upstream `PrismLauncher` path.

## Architecture boundary

- SwiftUI and AppKit own presentation and user interaction.
- Objective-C++ files in `PrismNative/Bridge` adapt the existing C++ core.
- Qt and C++ types must not appear in public Objective-C headers.
- Swift receives immutable Foundation value objects and main-thread callbacks.
- The native target must remain runnable while backend capabilities are moved
  behind the bridge incrementally.

## Command-line verification

```sh
xcodebuild \
  -project macos/PrismNative.xcodeproj \
  -scheme PrismNative \
  -configuration Debug \
  -derivedDataPath .deriveddata-prism-native \
  CODE_SIGNING_ALLOWED=NO \
  build

plutil -extract CFBundleIdentifier raw \
  .deriveddata-prism-native/Build/Products/Debug/Prism.app/Contents/Info.plist
```

The identifier check must print `com.lloydME.Prism`. This verification builds
the app but does not launch it.
