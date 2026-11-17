# Dhara

**[বাংলায় পড়ুন](README.bn.md)**

Dhara is a Windows desktop app that turns the films, series and anime on
BDIX media servers into one library. It finds what is on the servers your
connection can reach, gives every title a poster and a page of its own,
and plays it from the server that answers fastest.

It is made for one person's own use, and it is a **client only**, like Kodi
or Infuse: it hosts nothing and shares nothing, and it has no accounts, no
ads and no telemetry.

## What it does

- **One library from many servers.** The app ships a list of 38 BDIX
  servers and tests which of them answer from your connection. It reads
  folder listings (Apache, nginx, IIS), h5ai pages and Emby/Jellyfin
  servers. A film that lies on several servers is one title with several
  copies.
- **Search while you type**, with filters for type, quality, rating, year
  and genre. The library is kept on your PC, so no server is asked.
- **Posters, descriptions, cast and episode names** from TMDB, with your
  own key. The Anime page adds AniList's seasonal and trending lists.
- **The player is inside the app** (libmpv): no VLC or codec pack is
  needed. It plays MKV, MP4 and the other usual files, with styled and
  picture subtitles, several sound tracks and hardware decoding.
- **Play starts on the fastest copy** in the quality you prefer. If a
  server stalls, the video goes on from another copy at the same position.
- **Resume, next episode with a countdown, My List and History.**
- **Seek steps of your own:** separate values for back and forward, used
  by the buttons and the arrow keys.
- **Everything works from the keyboard.**

## Install

Dhara needs Windows 10 or 11 (64-bit). The player and everything else it
uses come with it.

1. Run `Dhara-Setup-1.0.0.exe`. It is not published anywhere: it is made
   from this repository (see [Building it](#building-it)) and lies in
   `dist\` afterwards.
2. To check that a copy of the installer is the file that was made,
   compare its SHA-256 with the value in `Dhara-Setup-1.0.0.exe.sha256`:

   ```powershell
   (Get-FileHash Dhara-Setup-1.0.0.exe -Algorithm SHA256).Hash
   ```

The installer copies the app to `%LOCALAPPDATA%\Programs\Dhara` and adds a
Start Menu shortcut (a desktop shortcut if you tick it). It installs for
your user only and asks for no admin rights. It adds no service, no
start-up entry and no updater. A newer version is installed over the older
one by running its installer.

## First steps

Home shows these three steps, and where each stands, until the library has
something in it.

1. **Servers.** Open Server Discovery on the rail, press **Test all**, then
   **Enable all reachable**. Many BDIX servers only answer on certain ISPs,
   so only the ones your connection reaches are switched on.
2. **Index.** In Settings, open **Library index** and press **Update
   index**. The app reads the folders of the enabled servers; the first run
   over three servers took 15 to 20 minutes. Later runs are much shorter and
   start by themselves, once a day at most.
3. **Posters.** In Settings, open **Titles and matching**, add your TMDB
   key (the *API Read Access Token* of your TMDB account) and press
   **Match now**. Without a key everything else works; titles then have a
   drawn picture where the poster would be.

A single video plays without any of this: press Ctrl+O and paste its
`http://` address.

## Keys

In the app:

| Key | What it does |
|---|---|
| Ctrl+K or / | Go to the search field |
| Enter or ↓ in the search field | Go to the first result |
| Ctrl+O | Play a URL |
| Alt+←, the mouse's back button | Back |
| Esc | Leave a text field or close a dialog, otherwise Back |
| Tab, arrow keys, Enter or Space | Move between buttons, cards and rows, and press them |
| Page Up, Page Down, Home, End | Scroll the page |

In the player:

| Key | What it does |
|---|---|
| Space | Play or pause |
| ← and → | Skip back or forward by your seek step |
| ↑ and ↓ | Volume up or down |
| M | Mute |
| S | Next subtitle track |
| F, or a double-click | Fullscreen |
| N | Next video |
| I | Playback info: server, speed, buffer, decoder |
| Esc | Close the open panel, then leave fullscreen, then leave the player |

## Your data

Everything the app keeps is on this PC:

| What | Where |
|---|---|
| Library, My List, history and playback positions | `%APPDATA%\com.dhara\dhara\library.db` |
| Settings and your changes to the server list | `shared_preferences.json` and `sources.json` in the same folder |
| Downloaded posters (at most 300 MB) | `images` in the same folder |
| TMDB key | Windows Credential Manager, entry `Dhara/tmdb` |

The app contacts the servers you enabled, an address you paste into
"Play a URL", TMDB (only with a key; titles and years are sent) and
AniList (when the Anime page is opened; nothing about your library is
sent). It contacts nothing else and writes no log.

## Removing it

Uninstall Dhara from Windows Settings, Apps. That removes the app and its
shortcuts and leaves your data. To remove the data too:

- delete the folder `%APPDATA%\com.dhara\dhara`
- in Control Panel, Credential Manager, Windows Credentials, remove
  `Dhara/tmdb`

## Security

The servers are not trusted. What they send is parsed, never rendered or
run, and the player is locked down before it opens anything: no scripts,
no yt-dlp, no configuration file, and network protocols limited to
`http` and `https`. The whole review, rule by rule, is in
[docs/security-review.md](docs/security-review.md).

The largest known risk is the age of the bundled player: libmpv 0.36 with
FFmpeg 6.0, built in September 2023. Media decoders are where a hostile
file would attack, and this build gets no fixes. See
[Keeping the player up to date](#keeping-the-player-up-to-date).

## Keeping the player up to date

The player library is the dependency to watch. This is how it gets into
the app:

- `pubspec.yaml` pins `media_kit`, `media_kit_video` and
  `media_kit_libs_windows_video` to exact versions.
- The build script of `media_kit_libs_windows_video`
  (`windows/CMakeLists.txt` in that package) downloads one fixed libmpv
  archive, and the build puts its `libmpv-2.dll` beside the app. The app
  loads that file by its full path and no other.
- `tool/bundled-libraries.sha256` holds the SHA-256 of that file, and
  `tool/package.ps1` makes no installer from a different one.

To see which libmpv a build holds, look at the version stamp of the file
(today `v0.36.0-403-g652a1dd907`):

```powershell
(Get-Item dist\Dhara-1.0.0\libmpv-2.dll).VersionInfo.ProductVersion
```

**Every month or two, and before every new installer:**

1. Run `flutter pub outdated` and look at the three media_kit packages.
   If one is newer, read its changelog on pub.dev.
2. Raise the three versions together in `pubspec.yaml` (they are released
   to fit each other) and run `flutter pub get`.
3. Run `flutter build windows --release`, then `flutter test`. With a
   build in place, the tests drive the real `libmpv-2.dll`: every
   hardening option is set and read back, a playlist sent in place of a
   video must not open a file of this PC, and a video is played from a
   local web server. A failure here means an option changed its name or
   its meaning. Do not go on until it is understood.
4. Run `pwsh tool/package.ps1`. It stops, because `libmpv-2.dll` is no
   longer the file on the list, and prints the new SHA-256. Check where
   the new file comes from (the address and checksum in the package's
   `windows/CMakeLists.txt`), put the new hash into
   `tool/bundled-libraries.sha256`, and run the script again.
5. Install it and go through [docs/manual-test.bn.md](docs/manual-test.bn.md)
   (in Bangla): a film, a seek, subtitles, a second sound track, the end
   of an episode, and the decoder line of the info panel (the I key).
6. Write the new version into
   [docs/security-review.md](docs/security-review.md): finding 2 and the
   table of bundled libraries.

**As things stand on 2026-11-18, there is nothing newer to take.**
`media_kit_libs_windows_video` 1.0.11 is the latest version and about 20
months old, and the repository that made its libmpv builds
(`media-kit/libmpv-win32-video-build`) was archived in October 2024. So
step 1 finds nothing, and the bundled libmpv stays the build of September
2023.

**The way out has not been tried yet:** putting a newer `libmpv-2.dll` in
the place of the bundled one. `shinchiro/mpv-winbuild-cmake` on GitHub
publishes current Windows builds of mpv
(`mpv-dev-x86_64-<date>-git-<hash>.7z`, each with a SHA-256 on the release
page), and they hold a `libmpv-2.dll`. Before that can be relied on, these
need an answer:

- Does media_kit 1.2.6 work with it? Its bindings were made for the
  libmpv of 2023. The tests of step 3 show which options the newer mpv no
  longer takes.
- How does the file get into the build? `tool/package.ps1` has no switch
  for it. It would need one that copies the downloaded file, checked
  against the release page, over the bundled one before the hash check.
- What does it cost? That archive is 30 MB packed, against 24.9 MB for
  the whole installer today, and a full build of mpv has more in it than
  the app needs.

This is a job of its own. Until it is done, two things stand between a
hostile file and the decoder: the hardening, and the fact that the app
plays only what the servers you enabled, or you yourself, give it.

## Building it

You need Flutter (stable channel), Visual Studio 2022 Build Tools with the
*Desktop development with C++* workload, and Windows Developer Mode.

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows --release
```

To make the installer you also need
[Inno Setup 6](https://jrsoftware.org/isinfo.php)
(`winget install --id JRSoftware.InnoSetup -e`):

```powershell
pwsh tool/package.ps1
```

The script builds the release, compares every bundled library with the
SHA-256 list in `tool/bundled-libraries.sha256`, and writes the installer
and its checksum to `dist\`. An installer is only as trustworthy as the PC
it was built on.

## Measured

On the PC the app is made for (Ryzen 5 5500U, integrated graphics,
Windows 11), version 1.0.0, a library of 23,389 videos:

| | Goal | Measured |
|---|---|---|
| Cold start | under 2 s | 0.85 to 0.9 s |
| Search | under 100 ms | 2 to 7 ms by title |
| Playback start | under 2 s | 0.7 to 1.8 s on real BDIX servers |
| Installer | about 80 MB at most | 24.9 MB (83.7 MB installed) |
| Idle memory | | 213 to 225 MB working set on Home |

## What it cannot do yet

- 20 of the 38 servers in the list are websites of their own kind. The app
  can test them but cannot read them.
- Dolby TrueHD sound is not decoded; the player switches to another track
  of the file by itself.
- `https` servers with a self-signed certificate are refused.
- It was built and tried on Windows only.

## More to read

- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): how each part works, what
  was measured and tried, and the known gaps
- [docs/security-review.md](docs/security-review.md): the security review
- [docs/manual-test.bn.md](docs/manual-test.bn.md): what to try by hand
  after a new installer is made (in Bangla)
- [assets/sources/README.md](assets/sources/README.md): the format of the
  server list
- [BRIEF.md](BRIEF.md): the brief the app was built from

This product uses the TMDB API but is not endorsed or certified by TMDB.
