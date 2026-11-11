# Dhara (working name)

Personal desktop client for browsing, searching and streaming media from BDIX
servers. Windows first; the code stays portable to macOS/Linux.

It is a **client only** (like Kodi or Infuse): no hosting, no re-sharing, no
accounts, no ads, no telemetry. Personal use, not for distribution.

The full project brief lives in [BRIEF.md](BRIEF.md) (mirrored in `CLAUDE.md`).
A Bangla + English README is written in Phase 8.

## Status

| Phase | State |
|---|---|
| 0. Setup | Scaffold written; waiting for Flutter + C++ build tools on the dev PC |
| 1. Design prototype | All screens in the chosen "Aurora Glass" direction, waiting for approval: `design/prototype/index.html` |
| 2–9 | Not started |

## Prerequisites (Windows)

1. **Visual Studio 2022 Build Tools** with the *Desktop development with C++* workload
2. **Flutter SDK** (stable channel) on `PATH`
3. **Developer Mode** enabled (plugins need symlink support)

Run `flutter doctor` and fix anything it reports under "Windows toolchain".

## First-time setup

```powershell
# Generates the windows/ runner next to the hand-written scaffold.
flutter create --platforms=windows --project-name dhara --org com.dhara .
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

## Layout

```
lib/                 app code
test/                automated tests (run anywhere)
design/prototype/    Phase 1 clickable HTML prototype (no network calls)
assets/sources/      starter BDIX source list (Phase 3)
```
