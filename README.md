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
| 0. Setup | Done: empty app window builds and opens on Windows |
| 1. Design prototype | Done and approved ("Aurora Glass" direction): `design/prototype/index.html` |
| 2. Player | Done and tested on real BDIX links. Not yet tried: HEVC / 4K files and `https://` links (none found so far) |
| 3. Sources and server discovery | Done: starter list of 38 checked servers, Server Discovery screen (BDIX Tester, add / edit / remove, JSON import and export), adapters for folder listings, h5ai and Emby/Jellyfin. Tried from one BDIX connection on 2026-11-13: all 38 answered, 18 are readable. The 20 custom websites have no adapter yet |
| 4. Indexer | Done: SQLite + FTS5 library database, crawler in a background isolate, Library index screen with a plain search. A full crawl of three enabled servers (2026-11-13) found 23,389 videos in 15 to 20 minutes; a second run was much faster |
| 5. Metadata and dedupe | Done in code and in automated tests; see [Titles and metadata](#titles-and-metadata). On the real library: names read and copies merged (19,854 films, 72 shows), and a first TMDB run that matched about nine titles in ten. **Not yet tried on a real library:** the matching rules as they are now, episode data, posters from TMDB's image server, and anime on a server that has any |
| 6. Real UI | Under way: design tokens and window scale, the shared widgets, the app shell (own title bar, navigation rail), the frameless window, My List and watch history in the database, Home (banner, Continue Watching, rows of posters), the page of a title (film, or show with its episodes), film details from TMDB (genres, length, director, cast), search and browse, and the Anime page with AniList's covers are in; see [Shell and window](#shell-and-window), [Home](#home), [Title page](#title-page), [Search and browse](#search-and-browse) and [Anime](#anime). My List and History have their page, and so has Settings; Server Discovery, Library index, "Titles and matching", Needs review and the TMDB key dialog have the new look; the keyboard reaches everything (see [Keyboard](#keyboard)); the library's reads were timed on the real library and made faster. **Not yet looked at in the real Windows build:** the pages restyled last (they were checked as pictures drawn by the widget tests), frame rate while scrolling, and cold start |
| 7. Smart playback | Under way: the player is set up for streaming, with buffer size and hardware decoding in Settings, seeks to keyframes where that is quicker, has an info panel, a title's copies are pinged live, Settings has a preferred quality, Play starts on the fastest copy, a video that stalls goes on from another copy by itself, and the next episode's copy is chosen before this one ends (see [Smart playback](#smart-playback)). Still to come: the last measurements |
| 8–9 | Not started |

## Prerequisites (Windows)

1. **Visual Studio 2022 Build Tools** with the *Desktop development with C++* workload
2. **Flutter SDK** (stable channel) on `PATH`
3. **Developer Mode** enabled (plugins need symlink support)

Run `flutter doctor` and fix anything it reports under "Windows toolchain".

## First-time setup

The `windows/` runner is committed, so no `flutter create` is needed.

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows
```

The first build (and the first `flutter test`) needs internet access: the
`sqlite3` package downloads its prebuilt SQLite library from its GitHub
release and checks it against a SHA-256 that is part of the pinned package
(see [Library database](#library-database)).

If `flutter run` fails with hundreds of `Undefined name` errors in packages
(`immutable`, `visibleForTesting`, `sqlite3` …), or the app starts but
reports `No available native assets`, a package was missing when the build
first ran and the build cache remembers that. Run `flutter pub get`, delete
`.dart_tool\flutter_build` (or run `flutter clean`) and start again.

## Player hardening

Every player is created in `lib/features/player/secure_player.dart`. Before a
URL is opened, the app sets the restricted mpv options (`ytdl=no`,
`load-scripts=no`, `load-unsafe-playlists=no`, no auto-loaded external files,
FFmpeg `protocol_whitelist=http,https,tcp,tls,crypto`), reads each one back
from libmpv and refuses to play if any value is not what it expects.

`flutter test` also runs these checks against the real `libmpv-2.dll` once a
Windows build exists (`test/features/player/libmpv_hardening_test.dart`).

Known gaps, tracked for later phases:

- The bundled libmpv is mpv 0.36 / FFmpeg 6.0 from 2023-09-24, the last
  release of the now-archived `media-kit/libmpv-win32-video-build`.
- FFmpeg follows HTTP redirects itself, to any http(s) host, and this
  build has no option to stop it (checked: the DLL has no `max_redirects`).
  The app therefore follows redirects first, under its own rule (same host
  or a configured source, at most 5), refuses to play if the chain breaks
  it, and hands the player the final address (the live ping does this,
  see [Starting on the fastest copy](#starting-on-the-fastest-copy)).
  What is left: a server could
  still answer the player itself with a new redirect. Closing that needs a
  libmpv whose FFmpeg can limit redirects.
- If no server can be asked beforehand (unreachable, slower than 2 s),
  the video is opened unchecked and the player reports the real error.

## Smart playback

### Streaming set-up

After the hardening and before a URL is opened, every player is also set
up for streaming (`lib/features/player/player_tuning.dart`). media_kit's
own choices are replaced where they do not suit a desktop player:

| mpv option | Value | media_kit's own | Why |
|---|---|---|---|
| `hwdec` | `auto-safe` (`no` with Hardware decoding off) | `auto` | the graphics card decodes, but only with decoders mpv lists as safe |
| `cache-on-disk` | `no` | `yes` | what was read stays in memory; nothing of a video is written to disk |
| `demuxer-max-bytes` | 112.5 MB | 32 MB | how far the player reads ahead |
| `demuxer-max-back-bytes` | 37.5 MB | 32 MB | what stays behind, for skipping back without asking the server |
| `cache`, `demuxer-seekable-cache` | `yes` | `yes`, `auto` | read ahead always; skips inside the buffer do not go to the server |
| `network-timeout` | 5 s | 5 s | a silent server is asked again (FFmpeg reconnects where it was) |
| `hr-seek-framedrop` | `yes` | `no` | an exact seek does not finish the frames on the way to its target |

The two sizes are one buffer, split three to one: the Buffer size of
Settings, 150 MB unless changed. With the cache
on, mpv reads ahead until that is full, so read-ahead needs no option of
its own. Each value is read back from libmpv; one that did not take does
not stop the video (this is about smoothness, not safety). `flutter test`
checks the options against the real `libmpv-2.dll` and plays a short video
through them from a local web server
(`test/features/player/libmpv_tuning_checks.dart`, run by
`libmpv_hardening_test.dart` so that all libmpv checks share one process).

### Live ping

`CopyProber` (`lib/features/playback/copy_probe.dart`) asks the servers
for the copies of one film or episode, all at the same time, and reports
each as it answers: how long the server took, where the file really is
(after redirects), or why it cannot be played (gone, refused, no answer
within 2 s, a redirect to a host that is no source).

- One small request per copy: the first byte of the file is asked for
  (`Range: bytes=0-0`) and the connection is dropped once the answer's
  head is in. It goes through `SafeHttpClient`, so only to the configured
  sources, with redirects under the app's rules.
- The copies of a film, and of an episode in its side sheet, are asked as
  their list comes up, if there are at most 12 of them; trailers, samples
  and copies that cannot be played are not asked.
- A copy that answered counts as online and shows its time; one that did
  not shows "No answer" (the reason on hover) and goes to the end. Where
  nothing was asked, the server's last test counts, as before.

### Starting on the fastest copy

A video of the player's queue comes with every copy it can be played from
(`PlayEntry`, `lib/features/playback/smart_start.dart`). When it is
opened, the player asks all of their servers at once (the live ping
above, 2 s at most) and `chooseCopy` picks:

- the copy it was left unfinished on, if that server answers: the same
  file is gone on with
- otherwise the quality that suits **Preferred quality** best, and of
  that quality the copy that answered first. All are asked at the same
  moment, so the first to answer is the fastest; the slower servers are
  not waited for
- a copy that is gone, refused or redirected away is passed over. If no
  server answers, the first copy is opened unchecked and the player says
  what is wrong; if every copy is redirected to a host that is no source,
  nothing is played

If the copy it was left on is gone, another copy goes on from the same
position, and the old copy's position is forgotten once the new one has
its own. A copy picked from a title's list, and a pasted address, are
played from exactly there (one request, for where it leads). The answer
is also where the player is sent: it replaces the redirect check that
ran before every video.

### Files of Emby and Jellyfin servers

A folder listing gives its files to anyone; a media server gives them to
a signed-in session only. `MediaSessions`
(`lib/features/playback/media_sessions.dart`) signs in to such a server
the first time one of its videos is pinged or played (the adapter's
sign-in: the server's guest user) and hands out the request headers of
that session. The live ping and the player send them with every request
for a file of that server:

- the token is kept in memory only: never saved, never logged, and gone
  when the app closes
- it goes to the server that gave it and to no other host. The app's own
  requests do not carry headers across a redirect to another host, and
  where the chosen copy leads to another host the player is given no
  headers. What is left is the gap named under
  [Player hardening](#player-hardening): FFmpeg follows a redirect the
  server sends the player itself, and would take the headers along
- if the sign-in does not work (no guest user, server down), the file is
  asked for without a session, the server refuses it, and the copy counts
  as not answering
- if the server no longer takes a session (it answers 401 or 403), that
  copy counts as not answering this once, and the app signs in afresh
  the next time

Checked with a stand-in server in the automated tests, and with the real
libmpv fetching a file that is only given for the right header. **Not yet
tried on a real Emby or Jellyfin server** (none of the enabled servers is
one).

### The next episode, ahead of time

In the last 60 seconds of a video that has a successor in the queue, the
player asks the servers for the copies of that next video and chooses one,
exactly as it would on Play (`_readyNext` in
`lib/features/player/player_screen.dart`). When the next video starts,
by itself or with **Next**, it is opened from that copy at once, without
the wait for the servers. The answer counts for five minutes; each video
is asked for ahead of time once, and if nothing answered it is asked
again when it is opened. The info panel says "asked ahead of time".

Only the choice is made ahead: the video itself is not opened or read
before its turn. (mpv's own `prefetch-playlist` would do that, but its
manual calls it highly experimental, and the app does not hand mpv a
playlist.)

### When a video does not play on

`StallWatch` (`lib/features/player/stall_watch.dart`) is told the player's
state once a second and notices three kinds of trouble:

- the video was opened and nothing came within 10 s
- it should be playing and for 10 s its position does not move (a video
  the user paused is never in trouble). Only the position counts: after a
  seek into a part that never arrives, libmpv reports neither buffering
  nor an error
- libmpv says that it cannot open the copy at all (no video in it): that
  counts at once
- it "ends" far from its end: the server broke off and the player ran
  out of what it had read ahead. Such a video is not marked as watched,
  and the next episode does not start

If the video has a copy that has not had its turn, the player **goes on
from that copy by itself**, at the position the video was at, and says so
for a moment ("The server stopped sending. Switched to …"): the servers
of the remaining copies are asked again and the fastest is taken, as on
Play. Every copy gets one turn. The video it leaves stays as it is until
another copy has answered; if none does, or none is left, the player says
what is wrong and offers **Try another copy** (starts the round again)
and **Try again** (asks every copy, this one too). If the video moves on
by itself, the message goes away.

Where a video has more than one copy, the control bar also has a
**Switch server** button that goes to the next copy at any time. A video
that was paused stays paused; "No other copy answers." if none does.

Checked in the running app against a local web server that stalls, drops
the connection, or sends bytes that are no video (2026-11-16): each time
the video went on from the other copy at its position.

The position follows the video: the copy that was left keeps its
position until the new one has one of its own, then forgets it.

### Seeking

A video can only start decoding at a keyframe, and those lie some seconds
apart. An exact seek decodes from the keyframe before its target, which
takes a moment; a keyframe seek shows the keyframe at once but lands a few
seconds off. The player picks per seek (`lib/features/player/seek_math.dart`):

- a skip of up to 15 s (buttons, ← →) is exact: "back 10 seconds" is 10
  seconds
- a longer skip goes to a keyframe, beyond its target in the direction of
  the skip: 30 s forward lands 30 s or a few more ahead. Within the last
  30 s of a video every skip is exact
- a click or drag on the seek bar goes to the keyframe at or before the
  spot

Skips inside what is buffered (ahead, and the part kept behind) do not go
back to the server at all. media_kit's own seek is always exact.

### Playback info

`I` in the player opens a small panel, top left, that says where the video
comes from and how playing it goes (`lib/features/player/playback_info.dart`).
It is there for trying things on a real connection, where only numbers
tell what happened:

- the server (its name and address), how long it took to answer when it
  was asked for the video, how many copies were asked for and how many
  answered, and how long the video took to start (from opening it to the
  first moving picture)
- picture size, format and frame rate; whether the graphics card decodes
  (and with which decoder) or the processor does; the sound format
- how much lies buffered ahead (seconds and megabytes), how fast the
  server delivers, and how many frames were dropped
- any streaming option libmpv did not take

The numbers are read from libmpv once a second, and only while the panel
is open.

## Player keyboard shortcuts

| Key | Action |
|---|---|
| Space | Play / pause |
| ← / → | Skip back / forward by the configured seek step (repeats while held; see [Seeking](#seeking)) |
| ↑ / ↓ | Volume up / down by 5% |
| M | Mute / unmute |
| S | Next subtitle track (Off → first → ... → Off) |
| F | Fullscreen on / off (also: double-click the picture) |
| N | Next video in the queue |
| I | Playback info on / off (see [Playback info](#playback-info)) |
| Esc | Close the open panel, then the info panel, then leave fullscreen, then leave the player |

## Resume and "up next"

- The position of each video is saved every few seconds and when you leave;
  opening it again resumes there ("Start over" jumps back to the beginning).
  Positions in the first moments or the last 5% are not kept.
- "Play a URL" (on Home, or Ctrl+O) takes several URLs, one per line, and
  plays them in order. In the last 15
  seconds a countdown offers "Play now" / "Cancel"; otherwise the next video
  starts when the current one ends.
- Positions are kept for the 2,000 most recently watched videos in the
  library database (table `playback`). Positions an older build kept in the
  settings file are moved over once, at start-up. If the database file is
  ever replaced because it was damaged, the positions go with it.
- What was watched is noted in the watch history (table `watch_history`,
  the last 5,000 videos): a video enters it once it was watched far enough
  to be resumed, and is marked as watched when it ends or is left during
  the last 5%. It is written by the player together with the position
  (`lib/features/player/resume_store.dart`) and read through
  `lib/features/history/history_store.dart`.

## My List and History

One page with two tabs (`lib/features/my_list/ui/lists_screen.dart`), both
on the rail.

- **My List** is a grid of the titles saved with the My List button (on
  the banner and on a title's page), the one added last first. The round
  button on a poster takes it off. A title stays on the list while its
  videos are gone from every server.
- **History** lists the videos watched, day by day, the latest first:
  title, episode, when, on which server, and how much is left. A click
  (or Resume) plays it on from there; "Watch again" starts a finished one
  over. The bin takes one video out, "Clear history" (after asking) all of
  them; both also forget where the video was left, so it is no longer
  offered under Continue Watching.
- Both live in the library database on this PC and nowhere else.

## Settings

The cog at the foot of the rail (`lib/features/settings/ui/settings_screen.dart`).
Every control does something now and is saved as it is changed
(`lib/core/settings/settings_controller.dart`); settings whose feature is
not built yet (languages) are not shown.

- **Playback:** the seek step back and forward (5/10/15/30/60/90/120 s or
  a typed 1–600 s; the same values the player's own panel changes), the
  preferred quality (Auto, 4K, 1080p, 720p; see [Title page](#title-page)),
  autoplay of the next episode, subtitle size, the player's buffer size
  (50–500 MB) and hardware decoding (both count from the next video; see
  [Streaming set-up](#streaming-set-up)).
- **Appearance:** interface size (90/100/110/125%, on top of the size the
  window gives), whether the banner on Home rotates, and Reduce motion
  (hover zooms, fades and the banner change at once; the system's own
  setting does the same).
- **Keyboard:** the keys that do something, in the app and in the player
  (see [Keyboard](#keyboard)).
- **Library and metadata / Sources:** the way to "Titles and matching"
  (TMDB key, matching, Needs review), "Library index" and Server
  Discovery. The first two have no icon on the rail any more; Back leads
  from them to Settings.
- **Privacy and security:** what the app never does, and "Clear history".

## Subtitles and audio tracks

- Subtitles are drawn by libmpv itself (libass), so styled ASS subtitles and
  picture-based ones (PGS, VobSub) work. They move up while the control bar
  is showing.
- Size (50–200%) is saved; delay (±0.1 s steps) applies to the current video.
- The bundled libmpv has no decoder for Dolby TrueHD (or MLP), the first
  sound track of many 4K films. Such a track says "cannot be played" in the
  list, and when libmpv picks one, the player switches to another track by
  itself (the same language if there is one) and says so
  (`lib/features/player/track_options.dart`). DTS, E-AC3, AC3, AAC, FLAC and
  Opus are decoded.
- A long track name is shown on up to three lines.
- What libmpv reports as an error goes away after 8 seconds once the video
  plays; it stays while nothing is playing.
- "Load external subtitle…" accepts a local `.srt`, `.ass`, `.ssa` or `.vtt`
  file up to 20 MB. The file is checked (type, regular file, size) and is only
  ever handed to the player as a subtitle.

## Fonts

Inter (interface) and Plus Jakarta Sans (titles) are bundled in
`assets/fonts` as variable fonts and declared in `pubspec.yaml`; nothing is
fetched at runtime. Sources, licences (OFL 1.1) and checksums are in
[assets/fonts/README.md](assets/fonts/README.md). In code use
`DharaFonts.ui` / `DharaFonts.display`; a button `textStyle` replaces the
theme's, so name the family there explicitly.

## Design tokens and scale

`lib/theme/tokens.dart` holds every token of the approved prototype
(colours, text sizes, spacing, radii, shadows, motion, layout measures).
Sizes are written once, for a window 1280 wide, where one `rem` of the
prototype is 15 pixels. `test/theme/tokens_test.dart` reads the prototype's
token block and fails if a value differs or a token is missing.

`DharaScale` (`lib/theme/scale.dart`) sits above the app's navigator and
draws everything larger on wider windows, by the prototype's rule: 100% up
to 1280, about 118% at 1920, about 172% at 3840. Widths are in logical
pixels, so with Windows display scaling at 125% a 1920-pixel screen counts
as 1536 (107%). Text, artwork and spacing grow together; widgets never ask
for the window size to pick a font size.

## Shared widgets

`lib/widgets` holds the building blocks of the prototype, each drawn from
the tokens: `DharaButton` and `DharaIconButton`, `PillChip`,
`SegmentedPills`, `DharaBadge`, `DharaSwitch`, `GlassCard`, `Skeleton`
(the loading shimmer), `EmptyState`, `ToastHost` (short messages at the
bottom of the window) and `DharaLogo`. `page_parts.dart` has what the
working pages share: `PageHead`, `StatTile`, `NoticeBar`, `RowCard` (a
line of a list, a button if it can be opened), `DharaField` (the text
field) and `DharaDialog`.

Everything clickable is built on `Pressable`: it reacts to the mouse, is
reached by Tab and the arrow keys, is pressed by Enter or Space, and shows
the focus outline only while the keyboard is in use. Animations take no
time when the system asks for reduced motion.

`PlaceholderArt` draws a picture from a title's name, for titles without a
poster: a port of the prototype's generator, so the same name always gives
the same picture and nothing is downloaded. Icons are the rounded Material
icons that ship with Flutter, named in one place (`lib/widgets/icons.dart`).

### Keeping frames cheap

Flutter draws this app with Impeller on OpenGL ES (through ANGLE). There,
every gradient that is drawn costs about two render passes of its own, on
every frame, and a blurred shadow is filled pixel by pixel. Measured on
2026-11-16 (Ryzen 5 5500U, window maximised, the real library): a grid of
23 poster cards took 117 render passes a frame, 102 of them for the two
fades on each card. What repeats on a page therefore avoids both:

- the fade over a card is a small picture made once and stretched over
  each card (`lib/widgets/shade.dart`); it is a gradient only until that
  picture exists
- a card has a shadow only while the pointer or the keyboard is on it
- the name on a card without a poster has an unblurred shadow
- artwork drawn for a title without a poster (several gradients) is drawn
  into a small image once it has been on screen for 0.4 s, and the image
  is shown from then on (`lib/widgets/placeholder_art.dart`; the 120 used
  last are kept, about 20 MB)
- an anime the library lacks is dimmed by a tinted box, not by `Opacity`

After that the same grid takes 36 passes a frame, and the work per frame
on the graphics side is about half. The rail and the title bar still blur
what is behind them (11 passes).

`flutter run` starts a debug build, which builds new rows many times
slower than a release build does (frames of 40 ms and more while a grid
scrolls into new rows, against 2 to 5 ms in a profile build). For daily
use, run `flutter run --release`.

## Shell and window

`AppShell` (`lib/shell`) is the frame every page sits in: the app's own
title bar (Back, brand, search field, state of the servers, window
buttons), the navigation rail on the left, and the page between them. The
pages have a navigator of their own; no routing package is used. Home is
always the first page, a place of the rail opens on top of it and replaces
the place that was open, so Back always leads toward Home. The player is
not a page of the shell: it opens above it and takes the whole window.

The title bar and the rail are glass. A page may let artwork run on under
them, to the window's corner (`ArtUnderShell` in `lib/shell/page_bleed.dart`:
Home's banner, the backdrop of a title); while that artwork is at the top,
the bar is clear over it, and once the page has scrolled the bar blurs what
passes beneath. These two and the copies sheet are the only places that
blur what is behind them.

### Keyboard

Everything can be done without the mouse; Settings lists these keys too.

| Key | Action |
|---|---|
| Ctrl+K or / | Put the keyboard into the search field; the results follow what is typed |
| Enter or ↓ in the search field | Go to the first result, past the filters; the arrow keys walk on from there |
| Ctrl+O | Play a URL |
| Alt+← , the mouse's back button | Back |
| Esc | Leave a text field or close a dialog, otherwise Back |
| Tab, arrow keys, Enter / Space | Move between and press buttons, cards and rows |
| Page Up, Page Down, Home, End | Scroll the page, wherever the keyboard is (`lib/shell/page_keys.dart`); in a text field Home and End move the caret |

Tab goes through a page first, then the title bar, then the rail. On
Settings it walks the list on the left before the settings themselves.
What takes the keyboard is scrolled into view, and Back returns it to the
card or row it left from. The player has its own keys (see
[Player keyboard shortcuts](#player-keyboard-shortcuts)).

On Windows the app draws the title bar itself. The runner
(`windows/runner/flutter_window.cpp`) takes the caption out of the window
frame when the app asks for it over the `dhara/window` channel and keeps
the system's left, right and bottom borders, so resizing, snapping, the
shadow and the rounded corners stay the system's. Moving the window, the
top resize edge and the three window buttons are the app's
(`lib/core/window`); while the player is open, its top strip takes that
role. No window package is used. If the runner does not answer (another
system, or a failure), the system's title bar stays and the app draws no
window buttons. The window cannot be made smaller than 940 by 560.

Not done: the snap layouts fly-out of Windows 11 over the maximize button
(Win+Z and dragging to a screen edge work), and the window cannot be moved
while a dialog is open.

### Trying a build without touching the real data

A build made with `--dart-define=DHARA_DATA_DIR=<folder>` keeps its
library, sources and pictures in that folder, its settings in memory, and
neither reads nor writes the TMDB key in Windows Credential Manager. A
build made without it has no such switch.

```powershell
flutter run -d windows --dart-define=DHARA_DATA_DIR=D:	mpdhara-test
```

## Sources

A source is one BDIX media server (`lib/features/sources/source.dart`). The
app ships a starter list, [assets/sources](assets/sources/README.md), which
also documents the JSON format and what the parser checks.

`SourceStore` keeps the starter list with the user's changes on top and
saves **only the changes** (added or edited sources, removed starter ids,
enabled ids) plus the last test result of each source to
`%APPDATA%\com.dhara\dhara\sources.json`. Untouched starter entries
therefore keep following the starter list across app updates. Nothing is
enabled by default. A damaged saved file is renamed to `sources.json.bad`
and the app carries on with the starter list; if the data folder cannot be
found, changes last for that run only.

Source lists never hold passwords: URLs with a user name or password are
refused.

The data folder is asked for through `path_provider_platform_interface`,
which `shared_preferences` already brings along with its Windows and Linux
implementations. The usual `path_provider` front package would add about a
dozen packages for platforms this app does not target; switch to it if
macOS support is added.

### Talking to servers

Everything the app fetches from a source goes through `SafeHttpClient`
(`lib/core/net/safe_http_client.dart`), built on `dart:io` with no extra
package:

- `http`/`https` only, and only to hosts the caller allows (the configured
  sources). Private addresses are not blocked; BDIX servers live there.
- Redirects are followed by hand, at most 5, and only to the first host or
  another allowed one. Request headers are not passed on to another host.
- One total time limit (15 s) and one size limit (4 MB, counted after
  decompression) per request; folder pages get 8 MB.
- No cookies, no proxy settings, and error messages never contain a URL.

### Adapters

One adapter per server type, all behind `SourceAdapter.list(folder)`
(`lib/features/sources/adapters`). An adapter only returns entries directly
inside the folder it was asked for: links to other hosts, other schemes,
upper levels or names hiding a `/` are dropped. Server HTML is parsed with
`package:html` and never rendered or run.

| Type | Adapter | Checked against |
|---|---|---|
| `directory_listing` | `DirectoryListingAdapter`: Apache (table and plain), nginx, IIS | real Apache and IIS pages; nginx and IIS-with-dates pages written by hand |
| `h5ai` | `H5aiAdapter`: reads the plain table every h5ai page carries | real DhakaFlix and CircleFTP pages |
| `emby`, `jellyfin` | `EmbyAdapter`: signs in (guest user by default) and reads the library API | a real Emby 4.8.5 server (2026-11-13): guest sign-in, library listing, item fields and the stream address. The automated tests use a stand-in server. **Jellyfin has not been tried on a real server** |
| `custom_site` | none yet | |

The sample pages are in `test/fixtures` (see
[test/fixtures/listings/README.md](test/fixtures/listings/README.md)).

### Server Discovery (BDIX Tester)

Open it from the rail, or by a click on the server count in the title bar. It lists every source with what the last
test found and offers:

- **Test all** (or "Test now" on one row), and **Enable all reachable**,
  which switches on every source the app could read. Custom websites answer
  but stay off: there is no adapter for them yet. One can still be switched
  on by hand; the app then says that nothing of it will be in the library,
  and Library index lists it as a website it cannot read.
- **Add source**, and Edit / Remove from a row's menu. The form uses the
  same checks as the list parser.
- **Import** and **Export** of the list as JSON. An import shows how many
  sources are new or changed before anything happens, never enables
  anything, and switches off a source it replaces until that is tested
  again. An export does not say which sources are enabled.

Enabled sources are tested again when the app starts once their last test
is a week old, so dead servers get marked. Nothing is switched off
automatically.

`SourceTester.testAll(sources)` (`lib/features/sources/source_tester.dart`)
fetches the first page of every base URL, a few sources at a time, and
reports each source as soon as it is done:

- reachable or not, and the response time ("ping")
- the detected server type, whatever the list claims: h5ai, folder listing,
  Emby/Jellyfin (asked through its public info address), or "other website"
- the server software, how many entries the first page lists and the first
  few names
- for anything unusable, the reason in plain English

A source is *readable* when it answered, an adapter exists for what it
turned out to be, and listing it worked. Each run uses an HTTP client that
only knows the hosts of the sources being tested: no port scanning, no
address sweeps, and a redirect to any other host is refused.

Emby/Jellyfin video URLs need the session token as a request header; the
player and the live ping send it (see
[Files of Emby and Jellyfin servers](#files-of-emby-and-jellyfin-servers)).
Known gap: `https` servers with self-signed certificates are refused.

## Home

Home (`lib/features/home`) starts with a banner of up to five featured
titles (the newest well rated films and shows that have a backdrop; the
same five for a whole day), then Continue Watching, then the library as
rows of posters, each row scrolling sideways: Recently Added, Movies,
Series, Anime and Top Rated. A row with nothing in it is left out, and so
is the banner when no title has a backdrop (no TMDB key yet).

- The banner moves on every nine seconds, holds while the pointer is over
  it, and does not move when animations are switched off. Its small
  pictures pick a title. Play (or Resume) plays without asking for a copy,
  My List keeps the title, the round button opens its page.
- Continue Watching lists the videos left unfinished, a film or show once,
  with how much is left. A click plays it on; for an episode the ones
  after it follow. A video played from a pasted address is listed too.

| Row | What is in it |
|---|---|
| Recently Added | Titles by their newest video: the date the server gives the file, or else when the app first saw it. A date later than that is not believed |
| Movies, Series | The newest year first; within a year, the ones most people voted on |
| Anime | Animation from Japan (TMDB genre and language), and what AniList knows |
| Top Rated | By TMDB rating, both kinds; only titles with at least 300 votes |

- Only titles with a video on an **enabled** server are shown, and a card
  counts only those videos.
- Titles TMDB was asked about and does not know are left to search; titles
  not looked up yet are shown, with artwork drawn from their name. So Home
  works without a TMDB key, and says once where posters would come from.
- A card shows the best quality any of its videos has and the rating; under
  the pointer (or the keyboard) it also shows year, genres and how many
  copies or episodes there are. A click opens the [title page](#title-page).
- With nothing to show, Home lists the three steps that fill the library
  (servers, index, TMDB key) and where each stands.
- `HomeController` reads all of it in the library isolate, keeps it in
  memory so that Home opens at once, and reads again when sources are
  switched, names were read or titles were matched (at most every 12 s
  while a matching run is under way).
- The rows walk an index in the order they are shown in and stop when they
  are full. In the automated test, all of Home is read from 100,000 videos
  (20,000 titles) in 10 to 30 ms on the development PC, the slower end
  while other tests run beside it (the aim was 50 ms). On the real library
  (23,393 videos, 19,750 titles, three servers) it takes about 11 ms.
- Posters are fetched in TMDB's `w342` size, decoded no larger than they
  are drawn, and not asked for while a row is being flung. Cards never blur
  what is behind them.

## Title page

The page of a film or show (`lib/features/details`): backdrop under soft
glass, poster, rating, year, genres, description, Play and My List, a few
facts, and "More like this" (same kind and first genre; for a title without
genres, about the same year and language).

- **A film** lists every copy the enabled servers hold: server, file,
  quality, size and its **live ping**: as the list comes up, each copy's
  server is asked for that file, and the list is put in order by the
  answers (see [Live ping](#live-ping)). "Ping again" asks once more.
- **A show** lists its episodes by season (only those a server holds), with
  TMDB's name, still and description where it has them, and marks what was
  watched. A click plays the episode; the chip at its end opens a side
  sheet with that episode's copies. Videos that are no episode, trailers
  and samples are listed apart.
- **Which copy plays** when none is picked
  (`lib/features/playback/copy_choice.dart`): one on a server that answers
  (a live ping where there is one, else its last test), then the quality
  that suits the **Preferred quality** of Settings best, then the quicker
  server, then the larger file. "Auto (best)" takes the sharpest; a named
  quality takes that one, then the nearest below it, then the nearest
  above.
- **What Play plays** (`lib/features/details/next_to_play.dart`): the video
  watched last if it was left unfinished; after an episode that ended, the
  next one; otherwise the film, or the first episode. After an episode the
  following ones are queued, and the player counts down to the next as
  before. Each video is then played from its fastest copy (see
  [Starting on the fastest copy](#starting-on-the-fastest-copy)); a row of
  the copies list plays that very copy. The player shows the title
  ("The Bay · S1 · E2 · …") instead of the file name.
- "Fix match" opens the same dialog as Needs review, for any title.
- Director (or creators), cast, genres and length show once TMDB's page of
  the title was read (see [Film details](#film-details)).
- Not there yet: the subtitles a copy has.

## Search and browse

One page (`lib/features/browse`) is the search and the way to browse
Movies and Series: what is typed into the title bar and the filters on the
page narrow one grid of posters as they change. The rail's Movies and
Series open it with the type set.

- **What is found:** every film and show with a video on an enabled server,
  also the ones TMDB does not know (artwork drawn from the name); only what
  was set aside by hand is left out. Videos that are neither (clips, songs)
  are found by file name on the Library index screen, as before.
- **Search** is over the titles' names (and original names) with SQLite
  FTS5: every word must match, the last one as a prefix. What is typed is
  quoted, so it cannot act as query syntax.
- **Filters:** type (All, Movies, Series, Anime), quality (has a copy at
  least that sharp on an enabled server), TMDB rating (7+, 8+), year (this
  year, the two before, or older), and genres (all of the chosen ones).
  **Order:** relevance (with a search; otherwise newest), rating, newest,
  A–Z.
- A query is answered with the ids of all titles that fit, so the grid
  knows its length at once; the cards are read sixty at a time as the grid
  scrolls, and only those in view are built.
- Typing waits 120 ms for the next key before it asks; a filter asks at
  once; only the latest answer counts. A search typed on another page
  starts over everything: the filters of the last browse are taken off.
- Measured in the automated test, on 20,000 titles with 100,000 videos, on
  the development PC: a search 20 to 25 ms, listing everything 35 to 45 ms,
  several filters at once about 40 ms, a page of 60 cards about 1 ms (the
  aims were 100 ms for a search and 20 ms for a page).
- On a copy of the real library (23,393 videos, 19,750 titles), best of
  five: a search for a name ("spider man") 0.3 ms, for one letter 32 ms,
  three filters at once 17 ms, listing everything 66 ms, a title page
  13 ms. Before two changes the same took 57, 83, 91, 73 and 36 ms:
  how many titles there are in all, and which genres, is now asked once
  and again only when the library has changed (counting took longer than
  searching), and SQLite may keep 16 MB of the file in memory instead of
  2 MB. The very first read after the PC starts waits for the disk and
  took over a second in one measurement.

## Library index

The index is the list of every video on the enabled servers, kept so that
search is instant and nothing has to be asked of a server while browsing.

### Library database

`%APPDATA%\com.dhara\dhara\library.db` is one SQLite file
(`lib/core/db/library_db.dart`): the crawl state of each source, every
folder (which is also the crawl queue), the video files, their subtitles, a
full-text index (FTS5) over file names and folder paths, the playback
positions, since schema version 2 the titles those videos are copies
of (see [Titles and metadata](#titles-and-metadata)), and since version 3
My List, the watch history and the indexes Home reads by, and since
version 4 who made a title and when TMDB's page of it was read. A database of an
older version is upgraded in place and keeps what it holds (from version 2:
the unfinished videos start the history). **A build older than the file
cannot open it:** it runs with an empty index for that run and leaves the
file alone. The schema carries a version; a file made by a newer version of
the app is refused and left untouched, and a damaged file is set aside as
`library.db.bad` and replaced, since the index can be crawled again. If no
database can be opened at all (the file is not reachable, or SQLite itself
did not load), the app still starts, without index and search, and the
Library index screen says so.

SQLite comes from the `sqlite3` package (pinned), which bundles the native
library through its build hook: at build time it downloads the prebuilt
`sqlite3.dll` of that release from GitHub and checks it against a SHA-256
held in the package. Nothing else needs installing, and `sqlite3_flutter_libs`
is not used. To update SQLite, raise the `sqlite3` version in `pubspec.yaml`;
`test/core/db/library_db_test.dart` checks that FTS5 is still there.

`package:sqlite3` is synchronous, so the database lives in a background
isolate that holds the only connection (`lib/core/db/library_isolate.dart`).
The UI sends it work as top-level functions and never touches SQLite or
parses a folder page itself. All SQL takes its values as parameters.

### Crawler

`Crawler` (`lib/features/indexer/crawler.dart`) walks the folders of the
enabled sources through their adapters and keeps the index in step
(`IndexStore`, `lib/features/indexer/index_store.dart`):

- **What is kept:** files with a video extension (`mkv`, `mp4`, `m4v`,
  `avi`, `mov`, `webm`, `ts`, `m2ts`, `mpg`, `mpeg`, `wmv`, `flv`) and the
  subtitle files (`srt`, `ass`, `ssa`, `vtt`) that belong to one by name, in
  the same folder or in a `Subs` folder next to it. Everything else is
  ignored: never stored, never fetched.
- **Polite:** two folders of a source at a time, sources on one host in
  turn, six hosts side by side. A timeout, a connection error or a 408, 429
  or 5xx answer is tried again after 2 s and 8 s. After three folders in a
  row failed that way the source is left for the next run.
- **Limits:** 12 levels below a base URL, 50,000 folders per source, 20,000
  entries per folder, 15 s and 8 MB per folder page.
- **Allowed hosts:** the crawl's HTTP client only knows the hosts of the
  sources being crawled; a redirect or link elsewhere is refused. An
  Emby/Jellyfin session token stays in the isolate's memory and is never
  written to the database.
- **Incremental:** everything is saved folder by folder, so a crawl that
  was stopped (or the app closed) carries on where it was. A later crawl
  starts at the base URLs again but does not re-read a folder that held no
  folders last time and still shows the same date. Files and folders are
  removed from the index only after the folder that held them was read
  successfully and no longer lists them; a folder that cannot be read keeps
  what the index has.
- **Sources:** a disabled source keeps its files but is left out of search;
  a source removed from the list is removed from the index.

### Library index screen

Open it from Settings. It lists the enabled servers with what the
index holds of each, shows the progress of a crawl, and offers **Update
index**, **Stop** and **Full re-check** (reads every folder again, also
those that look unchanged). An enabled source without an adapter (a custom
website) is listed too, as one the app cannot read: it is not crawled and
not counted in "Servers indexed". The search box searches file names and
folder paths while you type (every word must match, the last one may be
unfinished); a result opens in the player. Titles are looked for on the
Search page; this box is for finding a file.

Once the index has been built, the app brings it up to date by itself: 15
seconds after start-up, if an enabled server was last crawled to the end
more than a day ago. The very first crawl only starts when you ask for it.

Measured with the automated tests: search over 100,000 files answers in
under 30 ms, and writing 100,000 files takes about 5 s.

Known gaps:

- Servers that give no dates (the ICC FTP IIS servers) are read in full on
  every crawl.
- A change inside a folder that does not change the folder's date (a file
  replaced under the same name, a new subtitle in `Subs`) is only noticed
  by a full re-check.
- Subtitles kept in one folder per episode (`Subs/<episode>/English.srt`)
  are not linked to their videos.
- In this screen's search the same file on two servers is two entries; the
  Search page has them under one title. The Emby server at
  `146.196.48.9` holds the same files as the folder-listing source
  `146.196.48.10`, so with both enabled every film of theirs has two
  copies.
- The 20 custom websites in the starter list have no adapter and are not
  indexed.

## Titles and metadata

The index is a list of files. This part works out which film or show each
file is a copy of, puts all copies under one title, and fetches posters and
descriptions for the titles. Everything but the pictures happens in the
library isolate.

### From file names to titles

`parseReleaseName` (`lib/features/metadata/release_name.dart`) reads a
file or folder name: title, year, season and episode (`S01E02`,
`S01E01-E03`, `1x02`, `Season-01 Episode-09`, `Episode 02`, `EP01`, and
`Show - 05` for anime), CD parts, trailers and samples, resolution, source,
codec, audio and release group. `identifyVideo` (`video_identity.dart`)
adds the folders: a folder named like a film names the one video in it,
season folders name the show, and folders like "Movies" or "TV Shows"
decide between film, show and "other" (clips, songs, tutorials). Every
video gets a key (`m|vivarium|2019`, `s|the bay`); videos with the same
key are copies of one title.

The names are read by themselves whenever the index has changed and no
crawl is running. `test/fixtures/names/library_names.tsv` holds 156 real
paths and names with the expected result.

### TMDB key

Posters and descriptions come from The Movie Database, with your own key:
Settings, "Titles and matching", "Add TMDB key". Paste the *API Read Access Token* (or the
v3 API key) from your TMDB account settings. The key is kept in **Windows
Credential Manager** (entry `Dhara/tmdb`), through `win32` and `ffi`
directly; it is never written to the settings file, the database or a log,
and never shown again. The app checks it with TMDB when it is saved.
Without a key everything else works; titles simply have no pictures.

This product uses the TMDB API but is not endorsed or certified by TMDB.

### Matching

"Match now" on the "Titles and matching" page (opened from Settings; it
also counts the films, shows and other videos) looks every title up
(`MatchController`, `title_matcher.dart`): by name and year, then without
the year, then by the name the file gives it. Candidates get up to 70
points for the name, 20 for the year and 10 for standing clear of the
runner-up:

- **85 and above:** the title takes TMDB's name, poster and description.
  Two spellings that turn out to be one film become one title.
- **60 to 84:** it takes them too, but is listed under Needs review.
- **below 60:** not found; tried again after 30 days.

A film two years off is never a sure match, nor is a name that only ends
like the one asked for. If the search by name and year comes back with
exactly one film of that year, it is taken as an unsure match even if the
names differ: TMDB also searches the other titles a film goes by, which is
how Hindi dub titles find their originals.

The run asks at most about 16 times a second (TMDB allows about 40), waits
as long as TMDB asks when told to slow down, and can be stopped and carried
on. What a search found is kept for 30 days, so nothing is asked twice;
each run first judges unsure and not-found titles again from those kept
answers, without a request. Once every title has been looked up the button
reads "Check again" and starts a run that does only that. The first run
starts when asked for; titles that later crawls add are looked up by
themselves.

After a run, the seasons and episodes of matched shows are fetched for the
seasons the library has (`EpisodesController`), and again every 14 days.

### Needs review

Opened from "Titles and matching". Lists the unsure and not-found titles.
A title opens with the candidates
TMDB offered (no new request); pick one, search by another name and year,
or leave the title as its files name it. A decision made by hand is final:
no later run changes it.

### Pictures

`RemoteImageStore` (`lib/core/images`) downloads a poster once and keeps it
in `%APPDATA%\com.dhara\dhara\images`. Only `image.tmdb.org` over https,
a fixed set of sizes and paths of the shape TMDB uses are asked for, and
covers of anime from `s4.anilist.co` (https, and only paths of the shape
AniList's covers have); a
download is at most 3 MB and is kept only if it starts like a JPEG, PNG or
WebP file. The folder is held below 300 MB by removing what was not looked
at for the longest. Four downloads run at a time, the picture asked for
last first (it is the one on screen). A download that broke off or timed
out is tried again after 15 s, and the picture on screen asks again by
itself up to three times; one the server refused is left alone for ten
minutes.

### Film details

A match (a search answer) brings name, year, description, rating and
pictures, but not genres, length or people. So TMDB's page of every matched
film is read once more, by id, in the background
(`film_details_controller.dart`): genres, length, director and the first of
the cast. Shows get their creators and cast with their seasons.

- One request per film, about fourteen a second: a library of 18,000
  matched films takes roughly twenty minutes the first time. It starts by
  itself after titles were matched or counted, makes way for a run of
  matching, and goes on next time from where it stopped.
- What was read is kept for good (`titles.details_at` says when). A title
  that is matched to another film has its page read again.
- With the genres in, Japanese animated films count as anime, and "More
  like this" goes by genre.

### Anime

The Anime page shows the anime the library holds (animation from Japan,
and what AniList's lists matched), then AniList's list of the season under
way and its trending list as rows of covers, each anime marked with whether
the library has it (a season of a show finds its show). One that is in the
library opens its page. AniList needs no key; the two lists are fetched
when the page is opened, twice a day at most, and nothing about the library
is sent. Covers come from AniList's picture server and are kept on disk
like posters; lists kept by an older build have no covers until they are
fetched again ("Ask again").

### What the app contacts for this

| Host | For | When |
|---|---|---|
| `api.themoviedb.org` | search, film, show and season details, key check | only with a key: during a match run, after it for details, or a search in Needs review |
| `image.tmdb.org` | posters, backdrops, stills | when a matched title is shown |
| `graphql.anilist.co` | two lists of anime | when the Anime page is opened |
| `s4.anilist.co` | covers of the anime on those lists | when the Anime page shows them |

All over https, each through its own client that knows no other host. Only
titles and years are sent.

### Measured

On the real library of 2026-11-14 (three servers, 23,389 videos):

- Upgrading the database from version 1 and reading every name: 6 s, in
  the background. Result: 19,854 films, 72 shows, 631 other videos; 874
  films are on more than one server.
- A search by title: 2 to 7 ms.
- The first matching run, under the first version of the rules and before
  the run was made faster: about 258 titles a minute. The pace of the run
  as it is now has not been measured against TMDB. Of 10,587 titles looked
  up by then, 9,349 were matched, 621 unsure and 617 not found. Judged
  again by the rules as they are now (from the kept answers), 382 of the
  unsure became sure and 171 of the not found became matches.

### Known gaps

- Bangla dramas whose episodes are numbered at the end of the name
  (`Uccho_Maddhomik_Shomadhan_02`) are not recognised as episodes unless
  the folder has the same name. Dated shows (`WWE Main Event
  (2018.12.06)`) come out as films without a year.
- Many Bangla natok and telefilms are not on TMDB and stay "not found".
- A title cannot yet be marked "not a film or show", nor changed from film
  to show; "Leave it as it is" takes it off the review list. A wrong match
  can be put right from the title's own page ("Fix match"). The database
  is ready for the first (`titles.set_aside`, which Home already honours);
  the second needs no new column. Neither has a button yet.
- Episodes numbered straight through (anime) get no episode names.
- The anime parts were tested with made-up names and a real AniList
  answer: none of the three servers tried so far has an anime folder.

## Settings

User settings (skip steps, volume, subtitle size) are saved by `shared_preferences` in
`%APPDATA%\com.dhara\dhara\shared_preferences.json`. Values are validated on
load, so a broken file falls back to defaults. No secrets are stored there:
the TMDB key is in Windows Credential Manager (see [TMDB key](#tmdb-key)).

## Layout

```
lib/                 app code
lib/theme/           design tokens, theme, window scale
lib/widgets/         shared widgets of the prototype
lib/shell/           title bar, navigation rail, navigation
lib/features/home/   Home: its queries, controller, banner, rows and cards
lib/features/details/  the page of a title: copies, episodes, what to play
lib/features/browse/   search and browse: query, controller, grid
lib/features/playback/ which copy to play, and opening the player
lib/features/        the other features: sources, indexer, metadata,
                     player, history, my_list
windows/runner/      the Windows window (frameless title bar support)
test/                automated tests (run anywhere)
test/fixtures/       saved server answers the adapter tests run against
design/prototype/    Phase 1 clickable HTML prototype (no network calls)
assets/fonts/        bundled Inter and Plus Jakarta Sans
assets/sources/      starter BDIX source list (Phase 3)
```
