# Dhara: roadmap after 1.0.2

What the user asked for on 2026-11-20, with what was found while answering
and what is still to be decided. Nothing on this list is started. The phases
that are done are in the status table of [DEVELOPMENT.md](DEVELOPMENT.md).

## Confirmed

- The green band under a 4K HEVC film is gone in 1.0.2 (`hwdec=auto-copy-safe`).

## Asked for

### 1. Two builds: development and production

- **Development**: for the user only. Server list, Server Discovery, Library
  index, "Titles and matching", Needs review and the TMDB key stay as they are.
- **Production**: to install on another PC or to give to a friend. Ready to
  use: no three steps on Home (`_GetStarted` in
  `lib/features/home/ui/home_screen.dart`), no indexing by hand, no API key.
- While the library fills by itself: a loader with a message, or a small
  progress display in the header, and Home is shown as soon as some films
  are there.

Proposed, not yet agreed:

- One codebase, two flavours chosen at build time (`--dart-define`), each
  with its own AppId and data folder so that both can be installed on one PC.
- The development build writes a **catalogue snapshot** (titles, files,
  TMDB ids, poster paths) and the production build starts from it. Posters
  come from `image.tmdb.org`, which needs no key.
- On first start the production build tests the servers by itself, switches
  on the ones that answer, and lists only titles that have a copy on one of
  them. After that it re-reads the servers in the background, with the
  progress in the header.
- Open: where the snapshot comes from (inside the installer, or downloaded),
  how titles found after the snapshot get their posters (wait for the next
  snapshot, or a TMDB key built into the production build), and how much of
  the title page's extra data (cast, episode names) the snapshot carries.

### 2. Updates from inside the app

- Wanted if it is not hard. Proposed: releases on GitHub; the app asks once a
  day for the latest version, shows "Update available", and on a click
  downloads the installer, checks its signature against a public key built
  into the app, and starts it. Never silent.
- Needs: a change to the brief (a new host, and running a downloaded
  installer after the check), a public place for the releases, and a signing
  key that never lives on the PC as it is now (so: after the reset).
- An unsigned installer shows Windows' SmartScreen warning on another PC.

### 3. A longer server list

- Source: <https://sites.google.com/view/bdixftpserverlist/media-ftp-servers>.
  Read on 2026-11-20: about 800 different addresses on about 670 hosts, under
  roughly 400 names. The starter list has 38 servers on 43 hosts, 29 of which
  are on that page.
- Proposed: take them in as candidates that are switched off, leave out
  addresses that are plainly not media servers (router pages and the like),
  let the user's PC test them (BDIX Tester), then name the type of each that
  answers. Many are inside one ISP's network (10.x, 172.16.x) and will only
  answer its customers.

### 4. Custom websites

- 20 of the 38 starter servers are custom websites without an adapter.
- Cost per site: saved sample pages, a parser of a few hundred lines, tests.
  The installed app barely grows; the codebase and the upkeep do (a site
  that changes its pages breaks its adapter). A site that only works by
  running JavaScript or after a login stays out (no WebView).
- Proposed: not all of them. After the longer list is tested, pick the few
  with the most content that is not already readable through a file server.

### 5. Renewing the libmpv pin

- Proposed: `tool/update-libmpv.ps1`, one command that finds the newest
  build, downloads it, checks the published SHA-256, rewrites
  `windows/libmpv.cmake` and `tool/bundled-libraries.sha256`, and runs the
  real-libmpv tests. A monthly job that does the same and opens a pull
  request is possible once there is CI.

### 6. Phase 9: downloads for offline viewing

- To be started. Not a small job: a queue, resuming a broken download,
  pause and cancel, progress, a Downloads page, a folder setting, subtitles,
  and playing the saved file (today the player is only ever given an
  http(s) address). It gets its own plan, six to eight increments.

### 7. The user's data on several PCs

- Wanted: free. What has to travel is small (My List, history and resume
  positions, settings, the source list), not the library database.
- Proposed: a sync file in a folder that the user's own cloud program
  (OneDrive, Google Drive) keeps in step; the app reads and merges it. No
  account in the app, no new host, no secret.
- Other ways looked at: Supabase's free tier (live, but an account, a login
  and a stored secret; a free project is paused after a week without use);
  Firebase (weak on Windows desktop).

### 8. Design

- Done on 2026-11-20: the filters on the search and browse page can be
  folded away (the "Filters" button).
- More versions of the logo to choose from (`lib/widgets/logo.dart`): a
  darker one, one with rounded corners on the play triangle and a changed
  wave under it, and a few more. Six were shown on 2026-11-20 (A is the
  logo as it is; B dark with a coloured mark; C rounded play and two waves;
  D deeper gradient and a longer wave; E dark with a stream of three waves;
  F the play over filled water). Chosen on 2026-11-20: **F** is the logo
  and the app's icon; A, B and C stay in the code as `DharaLogoStyle`
  (`classic`, `dark`, `rounded`) for later use. Two more were shown and
  wait for a word: B with a rounded play triangle, and a dark F.

## Still open from before

- The PC is to be reset; installers are made again and the TMDB key is
  replaced after that.
- The 4K film took 7.5 s to start (13 copies asked, 2 answered).
- Poster cards without a hover effect for a while, once, on a second PC.
- "No other copy answers." once or twice on Switch server.
