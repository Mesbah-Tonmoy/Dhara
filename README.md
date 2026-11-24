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

- **One library from many servers.** The app ships a list of 52 BDIX
  servers checked by hand, and some 400 more taken from a public list that
  nobody has confirmed yet, and tests which of them answer from your
  connection. It reads
  folder listings (Apache, nginx, IIS), h5ai pages, Emby/Jellyfin
  servers, and two websites of their own kind (FlixHub, Khulnaplex). A film that lies on several servers is one title with several
  copies.
- **Search while you type**, with filters for type, quality, rating, year
  and genre. The library is kept on your PC, so no server is asked.
- **Posters, descriptions, cast and episode names** from TMDB. The Anime
  page adds AniList's seasonal and trending lists.
- **Ready when it is installed.** The installed app fetches a library that
  was made beforehand, finds the servers that answer from your connection
  and keeps the library up to date by itself.
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

1. Run `Dhara-Setup-<version>.exe`. It is not published anywhere: it is made
   from this repository (see [Building it](#building-it)) and lies in
   `dist\` afterwards.
2. To check that a copy of the installer is the file that was made,
   compare its SHA-256 with the value in the `.sha256` file beside it:

   ```powershell
   (Get-FileHash dist\Dhara-Setup-*.exe -Algorithm SHA256).Hash
   ```

The installer copies the app to `%LOCALAPPDATA%\Programs\Dhara` and adds a
Start Menu shortcut (a desktop shortcut if you tick it). It installs for
your user only and asks for no admin rights. It adds no service, no
start-up entry and no updater. A newer version is installed over the older
one by running its installer. An app that was built for it also says when
there is a newer version (**Update** in the title bar) and, if you choose
**Download and install** there, fetches that installer, checks that it is
the one its maker signed, and starts it for you.

## First steps

**With the installer there are none.** The first time the installed app
starts it gets itself ready, and Home says how far that is ("Getting your
library ready"):

- it fetches the library (about 77 MB) from the address it was built
  with, and puts it in place, which takes a few minutes;
- meanwhile it tests the servers of its list and switches on the ones
  your connection reaches. Many BDIX servers only answer on certain ISPs.

After that Home shows the films and shows. From then on the app reads the
servers again by itself, once a day at most, and looks new titles up; a
small pill in the title bar says so while it does. If the library cannot
be fetched, Home says why and offers **Try again**, or **Read the
servers**, which builds the library from the servers themselves and takes
much longer.

The installed app is the **production build**: it has no pages for
building a library by hand. Those are in the **development build**, which
is what `flutter run` starts (see [Building it](#building-it)). There Home
shows these three steps, and where each stands, until the library has
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
| TMDB key | development build: Windows Credential Manager, entry `Dhara/tmdb`. The installed app carries a key of its own if it was built with one, and keeps none |

The app contacts the servers you enabled, an address you paste into
"Play a URL", TMDB (only with a key; titles and years are sent) and
AniList (when the Anime page is opened; nothing about your library is
sent). The installed app also asks, on its first start, the servers of its
list whether they answer, and fetches its library from the one address it
was built with: a plain download that sends nothing about you or your PC.
If it was built with an address for updates, it asks there once a day
whether a newer version exists (the same kind of plain request, which does
not even say which version you have) and tells you; it fetches and
installs nothing unless you click for it.
It contacts nothing else and writes no log.

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

The player is where a hostile file would attack, so the app does not ship
the libmpv that media_kit bundles, a build of September 2023 that gets no
fixes. It ships a current one in its place (mpv 0.42 of November 2026).
That holds only as long as newer builds are taken: see
[Keeping the player up to date](#keeping-the-player-up-to-date).

## Keeping the player up to date

The player library is the dependency to watch. This is how it gets into
the app:

- `pubspec.yaml` pins `media_kit`, `media_kit_video` and
  `media_kit_libs_windows_video`. media_kit drives libmpv; the libmpv it
  bundles itself is the one of 2023 and is left out of the app.
- `windows/libmpv.cmake` names one build of libmpv: an archive of the
  Windows builds that mpv.io lists (`shinchiro/mpv-winbuild-cmake` on
  GitHub), its address and its SHA-256. A build of the app downloads that
  archive once, keeps it in `windows/libmpv/` (not in git), uses it only
  if its SHA-256 is the one written there, and puts the `libmpv-2.dll`
  from it beside the app. The app loads that file by its full path and no
  other.
- `tool/bundled-libraries.sha256` holds the SHA-256 of that
  `libmpv-2.dll`, and `tool/package.ps1` makes no installer from a
  different one.

To see which libmpv a build holds, look at the version stamp of the file
(today `v0.42.0-38-gbcde6b93c`):

```powershell
(Get-Item dist\Dhara-*\libmpv-2.dll).VersionInfo.ProductVersion
```

**Every month or two, and before every new installer, take the newest
build:**

1. Run `pwsh tool/update-libmpv.ps1` (`-Check` only says whether there
   is a newer build). It finds the newest
   `mpv-dev-x86_64-<date>-git-<hash>.7z` of
   <https://github.com/shinchiro/mpv-winbuild-cmake/releases> (not the
   `v3` file, which only runs on newer processors), downloads it, and
   goes on only if its SHA-256 is the one GitHub shows beside it. Then it
   writes the three values of `windows/libmpv.cmake` (the file name, the
   date in the address, the SHA-256), the line for `libmpv-2.dll` in
   `tool/bundled-libraries.sha256`, and the build's name in this file
   and in the table of [docs/security-review.md](docs/security-review.md).
2. It then runs `flutter build windows --release` and the tests that
   drive the real `libmpv-2.dll`: every hardening option is set and read
   back, every script mpv starts by itself must be off, a redirect must
   not be followed, a playlist sent in place of a video must not open a
   file of this PC, and a video is played from a local web server. A
   failure here means an option changed its name or its meaning, or mpv
   has begun to do something new by itself. Do not go on until it is
   understood; the script says how to put the old pin back.
3. Run `flutter test`, all of it, and look at `git diff`.
4. Run `pwsh tool/package.ps1`, install what it makes and go through
   [docs/manual-test.bn.md](docs/manual-test.bn.md) (in Bangla): a film,
   a seek, subtitles, a second sound track, the end of an episode, and
   the decoder line of the info panel (the I key).
5. Commit. The script commits nothing.

The script was tried on 2026-11-20 in a copy of the repository that pinned
an older build: it took the build of 2026-11-11 and wrote exactly the
files as they are here. Its last part, the build and the tests, has not
run yet, as there was no newer build to take.

Do not wait much longer than that. On 2026-11-18 that source kept its
last 30 builds, the oldest less than six weeks old. Once the pinned build
is gone from there, a PC without the archive in `windows/libmpv/` cannot
build the app until a newer build is pinned.

Now and then also run `flutter pub outdated` and look at the three
media_kit packages. If one is newer, read its changelog, raise the three
versions together in `pubspec.yaml`, build, and go through steps 3 and 4.

**What the first change of build took (2026-11-18).** mpv 0.42 has things
in it that the build of 2023 lacked, and the app had to switch them off
before it could ship: Lua scripts that mpv starts by itself, among them a
hook that runs `yt-dlp`, and a libcurl that opens `http` addresses past
the protocol whitelist. Findings 11 and 12 of the security review say
what was done. A newer build may bring more of that kind; the tests of
step 3 are there to notice.

**What was tried with it:** all automated tests, and in the running app a
video from a web server on this PC, which played with hardware decoding
and was sought in. **Not tried yet:** real BDIX servers, a file with
several sound tracks or subtitles, a Dolby TrueHD track (this build has a
decoder for it, the old one had none) and an `https` server.

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

There are two builds of the one code. `flutter run` and
`tool/package.ps1 -Dev` give the **development build**, with the pages
that build a library (Server Discovery, Library index, Titles and
matching, the TMDB key). `tool/package.ps1` without `-Dev` gives the
**production build**, which is ready to use and has none of them. To make
one that fills itself:

1. In the development build, open **Library index** and press **Write
   snapshot**. It writes the library to one file (77 MB for 577,000
   videos), without what you watched, your list or your key.
2. Put the file where the installed app can fetch it. On Google Drive:
   upload it, share it with "anyone with the link" and copy the link. A
   newer snapshot goes under the same link with "Manage versions".
3. Make the installer with that link, and with a TMDB key if the app is to
   show posters for what it finds later:

   ```powershell
   pwsh tool/package.ps1 -SnapshotUrl "<the link>" -TmdbKeyFile D:\keys\dhara-tmdb.txt
   ```

   The key file holds the key and nothing else and must lie outside this
   repository. The key becomes part of the program, so everyone who gets
   the installer can read it out: give the installer only to people you
   would give the key. `-SnapshotFile <file>` puts the snapshot into the
   installer itself (it then is about 77 MB larger), for a PC that cannot
   reach the link.

A snapshot is read as untrusted input: only videos on a server of the
app's own list are taken from it.

## Measured

On the PC the app is made for (Ryzen 5 5500U, integrated graphics,
Windows 11), a library of 23,389 videos:

| | Goal | Measured |
|---|---|---|
| Cold start | under 2 s | 0.85 to 0.9 s |
| Search | under 100 ms | 2 to 7 ms by title |
| Playback start | under 2 s | 0.7 to 1.8 s on real BDIX servers |
| Installer | about 80 MB at most | 48.3 MB (the app's files: 168 MB); with a snapshot inside, 120.9 MB |
| First start of the installed app | | Home filled 100 seconds after the start: 577,000 videos fetched (77 MB) and put in place |
| Idle memory | | 196 to 210 MB working set on Home |

## What it cannot do yet

- 16 of the 52 servers in the list are websites of their own kind. The app
  can test them but cannot read them.
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
