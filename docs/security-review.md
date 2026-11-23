# Security review (Phase 8)

A walk through section 7 of the brief (`BRIEF.md`), point by point: where the
code does it, how that is checked, and what was found. Done on 2026-11-17, with
1,438 automated tests passing, and brought up to date on 2026-11-18, when the
libmpv of 2023 was replaced by a current build (findings 2, 3 and 11 to 14).

Verdicts: **ok** (done and checked), **gap** (known and accepted, with the
reason), **fixed** (found in this review and put right), **later** (belongs
to a later increment of Phase 8).

`test/security/code_rules_test.dart` reads the source and fails when code is
added that breaks one of the rules marked *guard* below. It proves that
something is absent; what the code does is proved by the other tests named.

## Findings

| # | What | Weight | State |
|---|---|---|---|
| 1 | Request headers (an Emby session token, the TMDB key as a bearer token) went along on a redirect to the same host even from `https` down to plain `http` | low: only the first host itself could ask for it | **fixed** in `6fe94bd` |
| 2 | The libmpv that media_kit bundles is mpv 0.36 / FFmpeg 6.0 of 2023-09-24, the last build its authors made; decoders are the main attack surface and that one gets no fixes | was the largest known risk | **fixed** on 2026-11-18: the app ships a current build in its place (mpv 0.42 of 2026-11-11, pinned by SHA-256 in `windows/libmpv.cmake`). It stays fixed only while newer builds are taken: "Keeping the player up to date" in the README says how |
| 3 | FFmpeg followed a redirect the server sends the player itself, to any http(s) host, and took the request headers along; the build of 2023 had no option to stop it | low: the app follows redirects first under its own rule and hands the player the final address | **fixed** on 2026-11-18 with the newer libmpv: the player follows no redirect at all (`max_redirects=0`). What is left is finding 13 |
| 4 | media_kit's build script checks the libmpv and ANGLE downloads by MD5 only | low: fetched over https from GitHub releases | **fixed**: `tool/package.ps1` compares the SHA-256 of every bundled library with `tool/bundled-libraries.sha256` and makes no installer if one differs or is not listed |
| 5 | One made-up device id is given to every Emby/Jellyfin server, so two operators could tell it is the same installation | very low: random, says nothing about the PC | **gap**, accepted |
| 6 | A file or folder name may hold Unicode direction marks, which can make a name read differently from what it is | very low: names are only shown and played, never run or saved under that name | **gap**, accepted |
| 7 | `packages/media_kit/assets/web/hls1.4.10.js` (a web-only file of media_kit) is in the bundle | none: nothing in the app can run a script | noted |
| 9 | media_kit's ANGLE download carries a `zlib.dll` that is a debug build (it imports `VCRUNTIME140D.dll`) | none: no file of the app imports it or names it | **fixed**: left out of the installed app |
| 8 | This PC's own certificate store holds a root that should not be there (found 2026-11-16), so `https` from this PC can be read on the way | outside the app | the TMDB key should be replaced after the PC is reset |
| 10 | media_kit, left to find libmpv itself, first loads whatever library the `LIBMPV_LIBRARY_PATH` environment variable names | low: whoever can set a variable for this user can already start programs as them | **fixed**: the app names the `libmpv-2.dll` beside the program by its full path. Tried on 2026-11-18 with the variable naming another copy of the library: the one in the app's folder was loaded |
| 11 | The newer libmpv has Lua in it, and there mpv starts scripts of its own: the yt-dlp hook, which runs a program called `yt-dlp` for an address that does not open, if the PC has one; a statistics overlay; a console; menus. The build of 2023 had no Lua | would have been high (the hook) | **fixed** before it shipped: `ytdl=no` shuts the hook down, and every `load-…` option the build lists is switched off and read back, so a script a later mpv adds is covered too |
| 12 | The newer mpv opens http(s) with a libcurl of its own, which knows nothing of the FFmpeg protocol whitelist, follows up to 16 redirects and speaks ftp as well | would have been medium | **fixed** before it shipped: `curl-enabled=no`, so http(s) goes through FFmpeg as before |
| 13 | A playlist that a server sends in place of a video can name a video on another http(s) host, and the player fetches it (never a file of this PC: a test checks that) | low: only a server the user enabled can send one, and the other host gets nothing but a request | **gap**, as it was before the update: mpv has no option to refuse playlists, and its rule knows protocols, not hosts |
| 14 | The newer build is a whole mpv: it reads more file formats and has more decoders than media_kit's cut-down one (Dolby TrueHD among them) | more code that reads what a server sends, but code that is maintained | accepted |

Not findings, but worth knowing:

- "Play a URL" plays from the host the user pastes, which need not be a
  source: the user's own act, and still `http`/`https` only.
- A redirect while playing may lead to any *configured* source, enabled or
  not, as the brief words it. Crawling and testing only know the hosts of
  the sources being crawled or tested.
- `https` servers with a self-signed certificate are refused.

## Player

| Rule | Where | Checked by | |
|---|---|---|---|
| `load-scripts=no`, `ytdl=no`, `config=no`, `load-unsafe-playlists=no`, nothing loaded on mpv's own initiative, none of mpv's own scripts running (`osc=no` and every `load-…` option the build has) | `lib/features/player/secure_player.dart`: set after libmpv starts, each value read back, playback refused on a mismatch | `secure_player_test.dart`; `libmpv_hardening_test.dart` against the real `libmpv-2.dll`, which also sees mpv shut the yt-dlp hook down | ok (finding 11) |
| FFmpeg protocols limited to `http,https,tcp,tls,crypto` | the same file: `stream-lavf-o` and `demuxer-lavf-o`, and `curl-enabled=no` so that it is FFmpeg that opens http(s) | the same tests | ok (finding 12) |
| The player follows no redirect | the same file: `max_redirects=0` in `stream-lavf-o` | `libmpv_hardening_test.dart`: a redirect is followed by a player left as it comes and refused by a hardened one, which still plays the address itself | fixed (finding 3) |
| The player is only ever given an `http`/`https` address | `parseMediaUrl` (`lib/core/net/media_url.dart`) on every pasted and every indexed address. The whitelist above is FFmpeg's: mpv itself can open a local path, which the app uses for a subtitle file the user picks, and for nothing else | `media_url_test.dart` | ok |
| What a server sends cannot make the player open something on this PC | `load-unsafe-playlists=no`, and mpv's own rule for edit lists that come over the network | `libmpv_hardening_test.dart`: a playlist and an mpv edit list (EDL), served in place of a video and naming a local file, are refused by the real libmpv, while the same list naming the server's own video plays | ok |
| A player is made in one place only | `createPlayer()` | *guard* | ok |
| libmpv is the file beside the program | `_bundledLibmpv()` in `lib/main.dart` hands media_kit the full path, so no environment variable and no search by name decides which library is loaded | *guard* | fixed (finding 10) |
| No mpv command that runs or loads something | the app sends `seek` and sets subtitle and audio properties | *guard* | ok |
| Option names are those of the bundled mpv | read back at run time; compared with the 0.36 manual in Phase 2 and Phase 7, and for mpv 0.42 every option was read back and every behaviour test run on 2026-11-18 | `libmpv_hardening_test.dart`, `libmpv_tuning_checks.dart` | ok |
| Decoder itself | a current libmpv in place of the one media_kit bundles (`windows/libmpv.cmake`) | `libmpv_hardening_test.dart` fails if the build holds mpv 0.36; *guard* (the pin) | ok while it is kept current (finding 2) |

## Network

| Rule | Where | Checked by | |
|---|---|---|---|
| Only enabled sources, TMDB and AniList are contacted | every request goes through `SafeHttpClient` (`lib/core/net/safe_http_client.dart`), made with the hosts it may reach: the sources being crawled or tested, `api.themoviedb.org`, `image.tmdb.org`, `graphql.anilist.co`, `s4.anilist.co` | *guard* (one `HttpClient`, no sockets, the four host names); `safe_http_client_test.dart`; the client tests of TMDB, AniList and pictures | ok |
| A production build also fetches its library snapshot, from the one https address built into it (since 2026-11-24; the brief has a line for it) | `SnapshotFetcher` (`lib/features/snapshot/snapshot_fetcher.dart`): its client knows that host and no other, so a redirect elsewhere is refused; no cookie, no header of its own, nothing about the user or the library in the request; `snapshotUrlFrom` takes only an https address without a user name or password. The address is a build-time value (`DHARA_SNAPSHOT_URL`), not in the code. What comes back is only saved as a file and then read as untrusted input (see below): finding 8 is why that matters, since https from a PC with a false root can be changed on the way | `snapshot_fetcher_test.dart`; *guard* (no host named in the code) | ok |
| On its first start a production build tests servers nobody switched on | `FirstStartController`: the servers of the starter list that were checked by hand, at their listed addresses only, once, while none is switched on; the ones the app can read are switched on. The candidates and the websites are not asked | `first_start_controller_test.dart` | ok (the brief has a line for it) |
| TMDB and AniList over `https` | `Uri.https(...)` in `tmdb_client.dart`, `anilist_client.dart`, `image_store.dart` | their tests | ok |
| `http`/`https` only, no scheme from a server | `parseMediaUrl` (`lib/core/net/media_url.dart`); `childEntry` (`listing_parser.dart`) drops links to other schemes | `media_url_test.dart`, `listing_parser_test.dart`; *guard* (no other scheme written in code) | ok |
| Redirects: same host or a configured source, capped | `_redirectTarget`, at most 5; headers stay with the first host and do not go from https to http | `safe_http_client_test.dart` ("redirects") | fixed (finding 1) |
| Redirects the player follows | none: `max_redirects=0` | `libmpv_hardening_test.dart` | fixed (finding 3); a playlist may still name another host (finding 13) |
| Every request has a time limit and a size limit | 15 s and 4 MB by default (8 MB for a folder page, 3 MB for a picture), counted after decompression. The snapshot is the one answer that goes to the disk as it arrives (`SafeHttpClient.download`): 512 MB at most, an hour in all, and given up when nothing has arrived for 30 s | `safe_http_client_test.dart` ("the size limit", "the time limit", "download") | ok |
| A video stream | no size limit can apply; `network-timeout` 5 s, and the stall watch | `stall_watch_test.dart` | ok |
| Private addresses are not blocked | no such check exists | `safe_http_client_test.dart` runs against 127.0.0.1 | ok |
| No proxy, no cookies, certificate checks left on | `HttpClient()` as it comes; no `findProxy`, no `badCertificateCallback` | *guard* | ok |
| No port scanning, no address sweeps | the tester, the crawler and the first start ask only the addresses in the list | `source_tester_test.dart`, `crawler_test.dart` | ok |

## Untrusted input

| Rule | Where | Checked by | |
|---|---|---|---|
| A real HTML parser, no regular expression over markup | `package:html` in the two listing adapters, the FlixHub and Khulnaplex adapters, `portal_links.dart` and `source_tester.dart` | adapter tests against saved pages; *guard* (who imports it) | ok |
| Server HTML is never rendered or run; no WebView, no JavaScript | there is nothing in the app that could | *guard* | ok |
| Server strings are shown as plain text | Flutter's `Text` has no markup; names are shortened and stripped of control characters (`cleanServerText`, `_unsafeInName`) | widget tests; `listing_parser_test.dart` | ok (finding 6) |
| Parameterised SQL only | every value is a `?`; what is spliced into a statement is text written in the code (column lists, `?, ?, ?`) | *guard* ("database"); the store tests search for quotes and FTS syntax | ok |
| What is typed into search cannot act as query syntax | `ftsQueryFor` quotes every word | `index_store_test.dart`, `browse_store_test.dart` | ok |
| JSON from Emby, TMDB and AniList | every field is type-checked; ids must match `[A-Za-z0-9-]{1,64}`, tokens `[A-Za-z0-9._-]{1,256}`; texts are cut to a length | `emby_adapter_test.dart`, `tmdb_client_test.dart`, `anilist_client_test.dart` | ok |
| A source list that is imported | at most 2 MB and 2,000 sources; every address must be http(s) without a user name or password | `source_list_test.dart` | ok |
| A library snapshot that is read | `snapshot_reader.dart`: only the tables and columns it knows, every value checked for type, size and range, under the database's own strict types, checks and foreign keys; a source only if the source list has it, a crawl's starting folder only if it is a base URL of that source, a folder, a video and a subtitle only on a server (scheme, host, port) of their source, written the one way an address is written; lines of at most 64 KB, 4 GB unpacked, 20 million rows; a file that does not hold together (no head, no end line, another number of rows) is refused whole and what was read is taken out again. Only an empty library is filled | `snapshot_reader_test.dart` | ok |

## Files

| Rule | Where | Checked by | |
|---|---|---|---|
| Sanitised names, no path traversal | a link counts only if it points directly into the folder asked for: other hosts, upper levels and names hiding `/`, `\` or a control character are dropped (`childEntry`). Nothing is saved under a name a server gave: pictures are kept under names matching `^/[A-Za-z0-9_-]{1,64}\.(jpg\|jpeg\|png\|webp)$` | `listing_parser_test.dart`, `image_store_test.dart` | ok |
| Extension whitelist | `lib/features/indexer/media_files.dart`: 12 video and 4 subtitle extensions; everything else is neither stored nor fetched | `media_files_test.dart`, `crawler_test.dart` | ok |
| A picture must be a picture | at most 3 MB, kept only if it starts like a JPEG, PNG or WebP | `image_store_test.dart` | ok |
| An external subtitle | picked in the system's file dialog; `.srt/.ass/.ssa/.vtt`, a regular file, at most 20 MB; only handed to the player | `subtitle_file_test.dart` | ok |
| Nothing is executed or opened with another program | no `Process`, no shell, no link opened | *guard* | ok |
| Which files reach the file system at all | seventeen files import `dart:io`, one of them (`library_db.dart`) for its compression only | *guard* (the list) | ok |

## Secrets

| Rule | Where | Checked by | |
|---|---|---|---|
| The TMDB key is in OS secure storage | Windows Credential Manager, entry `Dhara/tmdb` (`lib/core/secrets/windows_credential_store.dart`) | `secret_store_test.dart`, `tmdb_key_test.dart` | ok |
| Never committed | the key is not in the repository; `.gitignore` covers `.env`, `*.key`, `secrets.json` | `git grep` for a bearer token, a JWT and `api_key=<value>` finds nothing | ok |
| Never logged, never in an error | the app writes no log; `TmdbException` and `SafeHttpException` carry fixed texts without addresses | *guard* (no log of any kind); `safe_http_client_test.dart` ("error messages name the host but never the path or query") | ok |
| Goes to TMDB only | as a bearer header, or as `api_key` in the address for a v3 key; the client knows one host | `tmdb_client_test.dart`; finding 1 | ok |
| An Emby/Jellyfin session token | in memory only, sent to the server that gave it | `media_sessions_test.dart`, `emby_adapter_test.dart` | ok |
| Source lists hold no passwords | addresses with a user name or password are refused | `source_list_test.dart` | ok |

## Privacy

| Rule | Where | Checked by | |
|---|---|---|---|
| No telemetry, analytics or crash upload | no such package and no such call | *guard* | ok |
| Logs stay local, rotate, hold no secrets | there are no logs | *guard* | ok |
| What leaves the PC | to a source: requests for its pages and files, as "Dhara"; to an Emby/Jellyfin server also a made-up device id (finding 5). To TMDB: titles and years. To AniList: nothing about the library | the client tests | ok |
| What is kept | library, history and My List in `library.db`; settings in `shared_preferences.json`; pictures in `images`; all under `%APPDATA%\com.dhara\dhara` | | ok |

## Least privilege

| Rule | Where | Checked by | |
|---|---|---|---|
| No admin rights | the program asks for `asInvoker` | *guard* (reads the built `dhara.exe`) | ok |
| No background service, no start-up entry | the runner writes no registry key and starts nothing | *guard* | ok |
| No silent auto-update | the app has no updater and contacts no host for one | *guard* (hosts) | ok |
| Per-user install | `installer/dhara.iss`: `PrivilegesRequired=lowest`, into `%LOCALAPPDATA%\Programs\Dhara`, no registry key, service, start-up entry, task or download | *guard* (reads the script); a silent install and uninstall of a test copy on 2026-11-17 wrote one `HKCU` uninstall entry and one Start Menu shortcut, nothing under `HKLM` or Program Files, and removed both again | ok |

## Supply chain

| Rule | Where | Checked by | |
|---|---|---|---|
| Few dependencies | 10 packages named in `pubspec.yaml` (plus Flutter), 2 for development | *guard* (the list) | ok |
| Pinned versions, `pubspec.lock` committed | exact versions; the lock file names a SHA-256 for every package | *guard* | ok |
| Nothing known against them | `flutter pub outdated` on 2026-11-17: the direct dependencies are the latest, no advisory is reported | by hand; again before a release | ok |
| SQLite | the `sqlite3` package downloads its library at build time and checks its SHA-256 | the package | ok |
| libmpv | one fixed archive of the Windows builds mpv.io lists (`shinchiro/mpv-winbuild-cmake`), downloaded over https by `windows/libmpv.cmake` and used only if its SHA-256 is the one written there; the `libmpv-2.dll` in it is compared once more before an installer is made | *guard* (the pin); `tool/package.ps1` | ok |
| ANGLE | downloaded by media_kit's build script, MD5 only; compared by SHA-256 before an installer is made | `tool/package.ps1` (tried with a wrong hash: it stops) | fixed (finding 4) |
| CI: Actions pinned to commit SHAs | there is no CI | | n/a; a workflow, if one is added, pins them |
| How to keep media_kit/libmpv updated | "Keeping the player up to date" in `README.md` and `README.bn.md` | the steps were gone through once, for the build of 2026-11-11 | ok |

## The bundled libraries

SHA-256 of the libraries in the release folder; the
packaging script compares against the same list in
`tool/bundled-libraries.sha256` (without `zlib.dll`, which is left out). They come from the pinned packages
(media_kit_libs_windows_video 1.0.11, sqlite3 3.9.1) and Flutter 3.47.9;
libmpv is the build pinned in `windows/libmpv.cmake`.

| File | SHA-256 |
|---|---|
| `libmpv-2.dll` (mpv v0.42.0-38-gbcde6b93c, from `mpv-dev-x86_64-20261111-git-bcde6b93cc.7z`) | `88504ee5560942a955405e99dfb5971368e4cf851321f36565bf2a667271db1b` |
| `flutter_windows.dll` | `30494fb08f9f101a8fbe42568110aaa160efbd7341f3cfe877dc14214be3a233` |
| `sqlite3.dll` | `643956b011d5c705c6eae79d93085f5b206e4bfecf5d57a05aea3e2242612028` |
| `libEGL.dll` | `b2590bd0692f0381fc45c20bf1c7f7f713c9ea19c7ea6bab62efdd1fadc4eaac` |
| `libGLESv2.dll` | `620bb6e38d7ed6c760a0cf4a8eb6a8f64b259b96ff286551cd32cefc6c35ca39` |
| `d3dcompiler_47.dll` | `5653bc7b0e2701561464ef36602ff6171c96bffe96e4c3597359cd7addcba88a` |
| `vk_swiftshader.dll` | `4f33eea716491972cb1ad123a78acef485f852581130d3f3a98a1981009004f2` |
| `vulkan-1.dll` | `3be9a95dd9019aa1aca47ade26f5c1c7c0047f3cf6f633d586c9ec0d3b459566` |
| `zlib.dll` | `82d5bf175cf882ac9afc1558b416e674606d055966bc09529076b28a498fc0e4` |

These were taken on a PC that is not trusted (finding 8): they say what
this build holds, not that it is what the publishers made. After the PC is
reset, build again and compare; a difference in `libmpv-2.dll` in particular
wants an explanation.
