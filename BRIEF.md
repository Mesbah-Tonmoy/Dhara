# Project brief: Personal BDIX desktop streaming app


## 1. Who I am and how to work with me

- I'm a **software engineer**. You can be technical, but **explain everything to me in plain, simple Bangla (বাংলা)**: plans, progress updates, decisions, test steps and summaries.
  - Code, code comments, file names and commit messages stay in **English**.
  - Keep technical terms in English where that's clearer (e.g., "isolate", "FTS5").
- Make reasonable technical decisions yourself and briefly explain the "why" in Bangla. Only stop to ask when a decision is really mine (product, design, or something irreversible).
- **Git: I commit myself.** Do **not** run `git commit`, `git push`, or create remote repos. Read-only git commands (`git status`, `git diff`) are fine.
- **After every working increment**, give me this exact block:

  ```
  ### ✅ Increment: <short name>
  কী হলো: <2–4 lines in simple Bangla: what changed and why>
  কীভাবে টেস্ট করবেন: <steps in Bangla>
  Files changed: <list>
  Commit message:
  <type>(<scope>): <summary in English, Conventional Commits style>

  <optional body in English>
  ```

  One increment = one small change that compiles, runs and makes sense as one commit.
- Before each phase, give me a short plan in Bangla: what you'll build and which increments it splits into. After each phase, give a short Bangla summary of what's done and what's next.

## 2. What we're building, and why

A **desktop app for my own personal use** to browse, search and stream movies, series and anime from **BDIX media servers**. These are Bangladesh's local-exchange FTP/media servers, which are very fast on Bangladeshi ISPs.

The inspiration is the Android app **Ctent** (ctent-app.vercel.app). It merges many BDIX servers into one Netflix-style app: unified search, posters, automatic fastest-server playback, and a great player.

**Scope**

- Personal use only: free, no payments, accounts, ads or telemetry, and no public distribution.
- It's a **client only**, like Kodi or Infuse. It never hosts or re-shares content, and it streams directly from servers to my PC.

**Priorities, in order**

1. Smooth streaming
2. A catalogue as rich as Ctent's
3. Lightweight and fast
4. A modern, eye-catching UI
5. Secure (section 7)

## 3. Decisions already made

| Area | Decision | Reason |
|---|---|---|
| Platform | **Windows desktop first.** Keep the code portable to macOS/Linux. | My PC is Windows |
| Web version | **No** | HTTPS pages can't load `http://` BDIX servers (mixed content), CORS blocks reading their listings, browsers can't play MKV/HEVC/AC3/DTS, and cloud servers can't reach BDIX |
| Framework | **Flutter** (stable) | Native performance and a fully custom UI |
| Player | **media_kit** (libmpv) + `media_kit_libs_windows_video` | The player is bundled inside the app, so **no VLC or other install is needed**, and it plays nearly all codecs and subtitle formats with hardware decoding |
| Data | **SQLite + FTS5** | Instant local search |
| Metadata | **TMDB** (my own API key, set in Settings) and **AniList** (no key) for anime | Posters, backdrops, ratings, episode info |
| Rejected | Electron (heavy) and Tauri (its WebView can't play MKV/HEVC) | |

You choose the packages for state management, routing, DB and HTTP. Use as few as possible: well-maintained, high pub.dev score.

## 4. Server list: I don't have one, so you build it

I have no BDIX server list. Building the starter source list is part of the job.

1. **Research.** Research publicly listed BDIX media/FTP servers. Good places to look are ISP-run media servers, public "BDIX tester" lists, and community lists. For each, record:
   - name
   - base URL(s)
   - server type (plain directory listing / h5ai / Emby / Jellyfin / custom site)
   - category (movies / series / anime / mixed)
   - which ISP runs it, if known
2. **Store it as data.** Keep the list in an editable `assets/sources/starter_sources.json` with a schema version, not in code. Users can add, edit, disable or remove entries in the app. The app also supports **importing and exporting** source lists as JSON.
3. **Built-in "BDIX Tester / Server Discovery" screen.** It tests every candidate in parallel with timeouts and shows:
   - reachable or unreachable
   - ping
   - detected server type
   - a sample of the content found

   Then it gives one-click "Enable all reachable". Many servers only work on certain ISPs, so **only servers reachable from my connection get enabled**.
4. **Re-test periodically**, or on demand, and mark dead servers.
5. **Tell me in Bangla** how many servers you found, how many types you saw, and which adapters each one needs.

Boundaries: only test the URLs in the list. **No port scanning or IP-range sweeping.**

## 5. Development phases

Each phase is split into small increments, each with its own commit message (section 1). **Don't start a phase until the previous one works.**

### Phase 0: Setup

- Check this machine (OS, Flutter, Visual Studio C++ build tools, git) and tell me in Bangla what's missing and how to install it.
- Scaffold the Flutter project with a `.gitignore`, `CLAUDE.md` (copy of this brief), README, lint rules and a test setup.
- If a local Windows build isn't possible, prepare a GitHub Actions Windows build workflow, but ask me before creating anything remote.

**Done when:** an empty app window opens on my PC.

### Phase 1: Design prototype (approval gate)

- Build a **clickable, high-fidelity prototype first**, before any real development: a single self-contained HTML file (inline CSS/JS) that I open in my browser.
- Use mock data with **fictional titles and generated placeholder artwork**. No network calls.
- **Screens:**
  - Home: hero banner plus rows for Continue Watching, Recently Added, Movies, Series, Anime and Top Rated
  - Title details for a movie, and for a series with a season/episode picker
  - Copies list: server, quality, size, ping
  - Instant search with filters
  - Player with all controls, including the **seek-step setting**
  - My List / History
  - Server Discovery (BDIX Tester)
  - Settings
- **Style:** dark, cinematic, large artwork, a soft glass blur over backdrops, subtle hover scale and glow, smooth transitions, skeleton loaders, and a custom title bar. Laid out for 1280px wide up to 4K.
- Start with **2 visual directions for the Home screen**. Once I pick one, apply it to every screen.
- Collect all **design tokens** in one place: colours, typography, spacing, radii, shadows, motion. These tokens become the Flutter theme later. Use bundled fonts such as Inter or Plus Jakarta Sans, never fetched at runtime.
- **Show me the prototype, explain it in Bangla, and wait for my approval.** Iterate on my feedback. Development starts only after I say it's approved.

### Phase 2: Player

- media_kit player, hardened (section 7).
- **Controls:**
  - play/pause and seek bar
  - **configurable skip/seek steps**: separate forward and back values, presets (5/10/15/30/60/90/120 s) plus a custom value, also used by the arrow keys and on-screen buttons, and saved in Settings
  - keyboard shortcuts (Space, ←/→, ↑/↓, F, M, S)
  - subtitle/audio track selection, external subtitles, subtitle size and delay
  - playback speed, fullscreen
  - resume position, next-episode countdown
- **Done when:** any `http://` video URL I paste plays smoothly.

### Phase 3: Sources and server discovery

- Source model, and building and loading the starter list (section 4).
- BDIX Tester screen, plus JSON import/export.
- Adapters behind one interface:
  - generic HTTP directory listing (Apache, nginx, IIS)
  - h5ai
  - Emby/Jellyfin APIs
  - anything else the research turns up
- Unit tests that run adapters against saved sample listings.

### Phase 4: Indexer

- Runs in a background isolate, incrementally, with progress shown in the UI.
- Polite crawling: concurrency limits, timeouts, retry with backoff, and depth and page limits.
- Video extension whitelist plus linked subtitle files, stored in SQLite + FTS5.

### Phase 5: Metadata and dedupe

- File-name parser: title, year, `S01E02` / `1x02` / `Episode 02`, quality, codec, release-group noise. Back it with lots of unit tests.
- TMDB matching with confidence scoring and a local cache, plus a "Needs review" screen for manual fixes.
- AniList trending and seasonal lists, matched against my library.
- Dedupe across servers (one title, many copies), with series grouped by season and episode.

### Phase 6: Real UI

- Implement the approved prototype in Flutter, connected to real data: Home, Details, Search, My List, History, Settings, Discovery.
- 60fps scrolling, and fully usable with the keyboard.

### Phase 7: Smart playback

- On Play, ping every copy in parallel and start on the fastest one at my preferred quality.
- Fail over automatically on stall or error, keeping the playback position.
- Pre-warm the next episode, tune mpv (`hwdec=auto-safe`, generous demuxer cache and read-ahead, fast seeking), and add a buffer-size setting.

### Phase 8: Packaging, security review and docs

- Per-user installer (Inno Setup or MSIX) plus a SHA-256 checksum.
- A full security self-review against section 7, reported to me in Bangla.
- A README in Bangla and English.

### Phase 9 (optional): Downloads for offline viewing

## 6. Performance targets

| Target | Goal |
|---|---|
| Cold start | < 2 s |
| Search | < 100 ms over 100k files |
| Playback start | < 2 s on a good BDIX link |
| Seeking | Feels instant |
| Idle memory and installer size | Installer ≤ ~80 MB. Report the actual numbers for both. |

## 7. Security (must-haves)

**Player**

- mpv set up with scripting off (`load-scripts=no`), no yt-dlp hook (`ytdl=no`), no user config (`config=no`), and no unsafe playlists.
- FFmpeg protocol whitelist limited to `http,https,tcp,tls,crypto`.
- Verify the exact option names against current mpv and media_kit docs.

**Network**

- The app only contacts enabled sources, plus TMDB and AniList over HTTPS.
- A production build also fetches the library snapshot from the one https address built into it, without cookies, with a size limit, and sends nothing about the user or the library. On its first start it tests the servers of the starter list (their listed URLs only) and enables the ones it can read.
- A production build that was given an update address also asks that one https address, at most once a day and when the user asks, whether a newer version exists, and on the user's click fetches the installer from the same host: without cookies, with a size limit, and sending nothing about the user, the library or the installed version.
- Only `http`/`https` schemes are allowed. Never use `file://` or other schemes coming from server responses.
- Redirects are allowed only to the same host or another configured source, and are capped.
- Every request has a timeout and a size limit.
- **Don't block private IP ranges.** Many BDIX servers use 10.x or 172.16.x addresses.

**Untrusted input**

- Use a real HTML parser (no regex), never render server HTML, and no WebView or JS execution.
- Escape all server strings in the UI, and use parameterised SQL only.
- A snapshot is untrusted input like a server's answer: it is parsed strictly, and a video's or folder's address is taken only if it lies on a server of the source list.
- An update notice is untrusted input like a server's answer: it is parsed strictly and believed only if its signature fits the public key built into the app. The installer's address is taken only if it is https and on the host of the update address.

**Files**

- Sanitised file names, protection against path traversal, the extension whitelist, and nothing is ever executed or auto-opened.
- Exception: on the user's click a production build starts the installer of a newer version that it fetched itself, after its size and SHA-256 were found to be the ones the signed update notice names. A file that fails that check is refused and removed. Nothing else is ever started.

**Secrets**

- Store the TMDB key in OS secure storage. Never commit it or log it.
- Exception: a production build carries a TMDB key given at build time from outside the repository; it is never committed, logged or shown. The development build keeps the key in OS secure storage.
- The key that signs updates: its private half never enters the repository, a build or the app; the public half is given at build time.

**Privacy**

- No telemetry, analytics or crash upload. Logs stay local, rotate, and contain no secrets.

**Least privilege**

- Per-user install, no admin rights, no background services, no startup entries, and no silent auto-update.
- An update is only ever offered: nothing is fetched or started without the user's click, the installer runs in the open, per user and without admin rights, and a development build never asks for updates.

**Supply chain**

- Keep dependencies to a minimum, pin versions, and commit `pubspec.lock`.
- In CI, pin Actions to commit SHAs.
- Document in the README how to keep media_kit/libmpv updated, since media decoders are the main attack surface.

## 8. Testing

- Automated tests that run anywhere: parser, adapters (against saved sample listings), DB, matcher, settings.
- **Real streaming tests must run on my PC.** BDIX servers are only reachable from Bangladeshi ISPs. For each phase, give me a short manual test checklist in Bangla.

---

**Go: start Phase 0, then Phase 1 (the design prototype), and wait for my approval before Phase 2.**
