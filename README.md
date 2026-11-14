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
| 6–9 | Not started |

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
  it, and hands the player the final address
  (`lib/features/player/playback_url.dart`). What is left: a server could
  still answer the player itself with a new redirect. Closing that needs a
  libmpv whose FFmpeg can limit redirects.
- If the server cannot be asked beforehand (unreachable, slower than 5 s),
  the video is opened unchecked and the player reports the real error.

## Player keyboard shortcuts

| Key | Action |
|---|---|
| Space | Play / pause |
| ← / → | Skip back / forward by the configured seek step (repeats while held) |
| ↑ / ↓ | Volume up / down by 5% |
| M | Mute / unmute |
| S | Next subtitle track (Off → first → ... → Off) |
| F | Fullscreen on / off (also: double-click the picture) |
| N | Next video in the queue |
| Esc | Close the open panel, then leave fullscreen, then leave the player |

## Resume and "up next"

- The position of each video is saved every few seconds and when you leave;
  opening it again resumes there ("Start over" jumps back to the beginning).
  Positions in the first moments or the last 5% are not kept.
- Paste several URLs (one per line) to play them in order. In the last 15
  seconds a countdown offers "Play now" / "Cancel"; otherwise the next video
  starts when the current one ends.
- Positions are kept for the 2,000 most recently watched videos in the
  library database (table `playback`). Positions an older build kept in the
  settings file are moved over once, at start-up. If the database file is
  ever replaced because it was damaged, the positions go with it.

## Subtitles and audio tracks

- Subtitles are drawn by libmpv itself (libass), so styled ASS subtitles and
  picture-based ones (PGS, VobSub) work. They move up while the control bar
  is showing.
- Size (50–200%) is saved; delay (±0.1 s steps) applies to the current video.
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

Open it from the start screen. It lists every source with what the last
test found and offers:

- **Test all** (or "Test now" on one row), and **Enable all reachable**,
  which switches on every source the app could read. Custom websites answer
  but stay off: there is no adapter for them yet.
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

Known gaps: Emby/Jellyfin video URLs need the session token as a request
header, which playback does not send yet; `https` servers with self-signed
certificates are refused.

## Library index

The index is the list of every video on the enabled servers, kept so that
search is instant and nothing has to be asked of a server while browsing.

### Library database

`%APPDATA%\com.dhara\dhara\library.db` is one SQLite file
(`lib/core/db/library_db.dart`): the crawl state of each source, every
folder (which is also the crawl queue), the video files, their subtitles, a
full-text index (FTS5) over file names and folder paths, the playback
positions, and, since schema version 2, the titles those videos are copies
of (see [Titles and metadata](#titles-and-metadata)). A database of version
1 is upgraded in place and keeps its index. The schema carries a version; a file made by a newer version of
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

Open it from the start screen. It lists the enabled servers with what the
index holds of each, shows the progress of a crawl, and offers **Update
index**, **Stop** and **Full re-check** (reads every folder again, also
those that look unchanged). The search box searches file names and folder
paths while you type (every word must match, the last one may be
unfinished); a result opens in the player. It is a working screen until the
real Home and Search screens arrive in Phase 6.

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
  Films and shows screen has them under one title. The Emby server at
  `146.196.48.9` holds the same files as the folder-listing source
  `146.196.48.10`, and its files cannot be played yet (see the Emby gap
  above), so it is best left disabled for now.
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
Films and shows, "Add TMDB key". Paste the *API Read Access Token* (or the
v3 API key) from your TMDB account settings. The key is kept in **Windows
Credential Manager** (entry `Dhara/tmdb`), through `win32` and `ffi`
directly; it is never written to the settings file, the database or a log,
and never shown again. The app checks it with TMDB when it is saved.
Without a key everything else works; titles simply have no pictures.

This product uses the TMDB API but is not endorsed or certified by TMDB.

### Matching

"Match now" on the Films and shows screen looks every title up
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

Lists the unsure and not-found titles. A title opens with the candidates
TMDB offered (no new request); pick one, search by another name and year,
or leave the title as its files name it. A decision made by hand is final:
no later run changes it.

### Pictures

`RemoteImageStore` (`lib/core/images`) downloads a poster once and keeps it
in `%APPDATA%\com.dhara\dhara\images`. Only `image.tmdb.org` over https,
a fixed set of sizes and paths of the shape TMDB uses are asked for; a
download is at most 3 MB and is kept only if it starts like a JPEG, PNG or
WebP file. The folder is held below 300 MB by removing what was not looked
at for the longest.

### Anime

The Anime screen shows AniList's trending list and the season under way,
each anime marked with whether the library has it (a season of a show
finds its show). AniList needs no key; the two lists are fetched when the
screen is opened, twice a day at most, and nothing about the library is
sent.

### What the app contacts for this

| Host | For | When |
|---|---|---|
| `api.themoviedb.org` | search, show and season details, key check | only with a key, during a match run or a search in Needs review |
| `image.tmdb.org` | posters | when a matched title is shown |
| `graphql.anilist.co` | two lists of anime | when the Anime screen is opened |

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
  to show; "Leave it as it is" takes it off the review list.
- Episodes numbered straight through (anime) get no episode names. Films
  get no genres. AniList covers are not shown.
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
test/                automated tests (run anywhere)
test/fixtures/       saved server answers the adapter tests run against
design/prototype/    Phase 1 clickable HTML prototype (no network calls)
assets/fonts/        bundled Inter and Plus Jakarta Sans
assets/sources/      starter BDIX source list (Phase 3)
```
