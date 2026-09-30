# Building locally for newer SMC firmware (macOS 15.8+)

This fork adds support for SMC firmware that removed the direct charging
control keys (`CH0C`, `CHTE`, `CH0I`) — first seen with the macOS 15.8.1
firmware. On these platforms the SMC itself enforces charge hysteresis limits
via three keys, which the daemon configures instead:

| Key    | Type | Meaning                                          |
|--------|------|--------------------------------------------------|
| `bfF0` | ui8  | Limit activation (`0x02` active, `0x00` inactive) |
| `bfD0` | ui32 | Upper charge limit in % (little-endian encoded)   |
| `bfE0` | ui32 | Lower charge limit in % (little-endian encoded)   |

The firmware charges only while the charge is below the lower limit and stops
at the upper limit. The activation key (`bfF0`) must be written last.

## Build and install

1. Replace the signing-related build settings with your own values
   (`DEVELOPMENT_TEAM`, `CODE_SIGN_IDENTITY`, `BT_CODESIGN_CN` in
   `Battery Toolkit.xcodeproj/project.pbxproj`, and the team ID prefix in
   `BatteryToolkit/BatteryToolkit.entitlements` as well as
   `me.mhaeuser.batterytoolkitd/me.mhaeuser.batterytoolkitd.plist` and
   `me.mhaeuser.batterytoolkitd/launchd.plist`).
2. Build:

   ```
   xcodebuild -scheme "Battery Toolkit" -configuration Release build
   ```

3. Copy the app from DerivedData to `/Applications`.
4. Re-sign:

   ```
   ./resign-local.sh
   ```

   (Set `CODESIGN_IDENTITY` to override the signing identity.)
5. Launch the app; approve the daemon installation when prompted.

A free Apple ID certificate is sufficient, but the Apple Worldwide Developer
Relations **G3** intermediate certificate must be installed (import
`AppleWWDRCAG3.cer` from apple.com/certificateauthority/ if codesigning
identities report as invalid).

## Tools and caveats

`tools/smc_probe.c` prints key info and values for the power control keys —
use it to check what the current firmware exposes after a macOS update.
`tools/smc_enum_keys.c` enumerates all SMC keys with a given prefix, e.g. to
discover the successor of a removed key.

Known limitations on this firmware generation:

- The power adapter key (`CHIE`) reads `0x08` here while powered via USB-C,
  where the daemon expects `0x00` for "adapter enabled". This may be specific
  to non-MagSafe power sources or a firmware semantic change; the adapter
  disable feature needs verification. The charge limit itself is unaffected.
- Later security updates (macOS 26.7+ / 27, see charlie0129/batt issues
  #151/#152) gate the `bf*` keys behind a private entitlement, which would
  disable charging control entirely on those builds. The firmware this fork
  was tested against (macOS 15.8.1, build 24H32) is not affected.