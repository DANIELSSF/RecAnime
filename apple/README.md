# RecAnime — Apple apps

Targets (generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from `project.yml`):

| Target | Platform | Bundle id |
|---|---|---|
| `RecAnime` | iOS 26 (iPhone) | `com.danielsantiago.recanime` |
| `RecAnimeWatch` | watchOS 26 (companion, runs independently) | `com.danielsantiago.recanime.watchkitapp` |
| `RecAnimeWatchWidgets` | watchOS 26 WidgetKit (complications) | `com.danielsantiago.recanime.watchkitapp.widgets` |

Shared code lives in `../packages/RecAnimeKit` (models, API client, stores) and `../packages/RecAnimeUI` (design tokens, components).

## Setup

```sh
brew install xcodegen
cp Configs/Local.xcconfig.example Configs/Local.xcconfig       # DEVELOPMENT_TEAM (Personal Team id)
cp Configs/Secrets.xcconfig.example Configs/Secrets.xcconfig   # Supabase URL/key, Google client ids
pnpm apple:gen                                                # or: cd apple && xcodegen generate
open RecAnime.xcodeproj
```

Both `Local.xcconfig` and `Secrets.xcconfig` are gitignored. Without them the app still builds (auth is disabled until
Supabase/Google values exist) and runs in the simulator without signing.

## Simulator

```sh
pnpm apple:build          # iPhone 17 Pro, iOS 26.5
pnpm apple:test           # unit tests
pnpm apple:watch:build    # Apple Watch Series 11 (46mm); runtime: pnpm apple:runtime:watch
```

Pair a watch simulator with the iPhone simulator once (`xcrun simctl pair <watchUDID> <iphoneUDID>`) so
WatchConnectivity works between them.

## Physical devices with a free Apple ID (Personal Team)

1. Xcode › Settings › Accounts › add the Apple ID. Copy the 10-character team id into `Configs/Local.xcconfig`.
2. iPhone and Watch: Settings › Privacy & Security › Developer Mode › on.
3. Run the `RecAnime` scheme on the iPhone (cable); on first launch trust the developer in
   Settings › General › VPN & Device Management. Run `RecAnimeWatch` on the paired Watch.
4. Free-account limits: builds expire after 7 days (re-run from Xcode), at most 3 sideloaded apps per device,
   10 App IDs per week (do not rename bundle ids), no push notifications / TestFlight.
