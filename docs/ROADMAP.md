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
  A first piece is in since 2026-11-21: a development build (every build
  but a release, or `--dart-define=DHARA_DEV=true`) has Library index and
  Titles and matching on the rail.
- **Production**: to install on another PC or to give to a friend. Ready to
  use: no three steps on Home (`_GetStarted` in
  `lib/features/home/ui/home_screen.dart`), no indexing by hand, no API key.
- While the library fills by itself: a loader with a message, or a small
  progress display in the header, and Home is shown as soon as some films
  are there.

Decided by the user on 2026-11-21 (the work itself is not started):

- One codebase, two builds chosen at build time (`--dart-define`; the
  switch `DHARA_DEV` is there already). On the user's own PC both use the
  same data folder, as the installed app and `flutter run` do today.
- The development build writes a **snapshot** of the library (videos,
  folders, titles with their TMDB data, episodes) and the production build
  starts from it. Measured on 577,000 videos and 90,778 titles: about 50 MB
  packed (videos 15.5, titles 14.7, episodes 12.5, the rest 8).
- **Where the snapshot comes from:** the user keeps it on their Google
  Drive, shared with everyone who has the link, and a newly installed
  production build fetches it from there. This changes two rules of the
  brief's section 7 (the app contacts a host that is neither a source nor
  TMDB nor AniList; what it fetches fills the library), so the brief gets a
  line for it. To be found out first: a file of this size is not handed out
  by Drive's plain download address without a confirmation step, and that
  step is nothing Google documents. The address is a build-time value, so
  another place (a release on GitHub) can stand in. A snapshot inside the
  installer stays possible as an option of `tool/package.ps1`, for a PC
  without a connection to Google; the installer is then about 100 MB.
  Whatever a snapshot says, a video's address is only taken if it lies on
  a server of the source list.
- **A TMDB key is built into the production build**, so that titles found
  after the snapshot get their posters and a title page its details. The
  user's reasoning: the app goes only to people they trust. What a key that
  is read out of the program can do: use up the request allowance, or get
  the key suspended by TMDB; then posters stop until a build with a new key
  is made. It gives no way into the user's TMDB account as long as it is
  the API key or the read-only token. It is given to the build from
  outside the repository (never committed), and it changes section 7's
  rule on secrets for this build only; the development build keeps asking
  for the key and keeping it in Windows' Credential Manager.
- On first start the production build fetches the snapshot, tests the
  servers of the starter list by itself (not the unchecked candidates),
  switches on the ones the app can read, and lists only titles that have a
  copy on one of them. After that it re-reads the servers in the
  background, with the progress in the header.
- The user ran the matching once more in the development build before the
  first snapshot (2026-11-21).
- Not part of it: updates of the app from inside the app (point 2).

The increments, as proposed: (1) what a production build hides, and a
development installer; (2) writing a snapshot; (3) reading one into an
empty library, with progress; (4) fetching it, and the first start of a
production build; (5) the key built in; (6) reading the servers again in
the background; (7) packaging, docs, version 1.1.0.

Found out on 2026-11-21, before the work began: **Google Drive does hand
a large file to a program.** The address
`https://drive.usercontent.google.com/download?id=<id>&export=download&confirm=t`
answered with the file itself for a public file of 476 MB and for one of
5 bytes: no cookie, no sign-in, no redirect, one host, with its length
and with ranges; 50 MB came in 106 seconds on the user's connection. The
plain download address gives the large file only as a page that asks to
confirm. None of this is documented by Google, so it can stop working;
the address is a build-time value, and a production build that cannot
fetch its snapshot is to read the servers by itself. The user's
repository on GitHub is public and has no release yet, so a release asset
can stand in later (it needs a second host: GitHub redirects). To put a
newer snapshot under the same link: Drive, "Manage versions", "Upload new
version".

Agreed with the user on 2026-11-23: the seven increments as above, and
three lines for section 7 of the brief, each written into it with the
increment that needs it (a production build fetches its snapshot from the
one address built into it and tests the starter servers by itself; a
snapshot is untrusted input; a production build carries a TMDB key given
at build time).

Done:

- **(1), 2026-11-23.** A release is a production build unless it is made
  with `DHARA_DEV`: no Titles and matching, Library index, Needs review or
  TMDB key, no three steps and no key notice on Home.
  `tool/package.ps1 -Dev` makes the development installer ("Dhara Dev",
  beside the production app). See "Development and production builds" in
  DEVELOPMENT.md. Until (4) to (6) are in, a production build cannot fill
  an empty library.
- **(2), 2026-11-24.** The Library index page of a development build has
  **Write snapshot**: the library as one gzip file of JSON lines, without
  what only this PC should know. On the user's library it is 76.6 MB (not
  the 50 MB estimated: the folders and what the file names say are in it
  too), written in 14 seconds.
- **(3), 2026-11-24.** A snapshot is read into an empty library
  (`readSnapshot`; **Read snapshot** on the Library index page of a
  development build, for trying it with a data folder of its own). It is
  read as untrusted input, and the brief says so now: only what lies on a
  server of the source list is taken. The user's snapshot went in whole
  (1.81 million rows, none left out) in about a minute and a half.
- **(4), 2026-11-24.** A production build makes itself ready the first
  time it starts: it fetches the snapshot from the address it was built
  with (`tool/package.ps1 -SnapshotUrl`, which takes a Google Drive share
  link), reads it, and meanwhile tests the hand-checked servers of the
  starter list and switches on the ones it can read. Home shows how far
  that is, and what to do if it fails. The brief has its line for this.
  Tried with a real production build on a data folder of its own, with the
  snapshot file laid into it: Home filled by itself in under two minutes;
  killed half way and started again, it cleaned up and filled again. Two
  faults that trial found were put right before the commit (a snapshot
  lying in the folder was not read by a build without an address; nothing
  kept a crawl from starting while a snapshot was being read).
  **Not tried: the fetch from Google Drive itself**, which needs the
  user's link.

Still to do: (5) the TMDB key built in, and matching by itself; (6)
reading the servers again in the background, with the progress in the
title bar; (7) packaging, README, manual test list, version 1.1.0. Until
(5) and (6) are done, no production installer should be handed out.

Needed from the user for (4) to be tried for real: write a snapshot with
the development build (Library index, **Write snapshot**), put it on
Google Drive, share it with "anyone with the link", and give the link to
`tool/package.ps1 -SnapshotUrl`.

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
- Many are inside one ISP's network (10.x, 172.16.x) and will only answer
  its customers.
- Step 1, done on 2026-11-20: 619 of them are in the app as candidates
  (`assets/sources/candidate_sources.json`, switched off, type not known
  yet); left out are the servers the starter list has, social networks and
  the like, and home-network addresses.
- Step 2, done on 2026-11-20: what the test finds a readable server to be
  becomes its type, a test run asks sixteen servers at a time in place of
  six, and Server Discovery can show only the readable servers or only
  those never tested.
- The user's test run, 2026-11-20 about 02:50 at night: of 657 servers 328
  answered and the app called 20 readable. Of the starter list 11 were
  readable and 15 did not answer, DhakaFlix and FTPBD among them, which
  answered on 13 and 17 Nov: that night's "did not answer" says little.
- Step 3, done on 2026-11-20: the front page of each candidate that
  answered was looked at once. One is a media server (CTGMovies' file
  server, now `ctgmovies-media` in the starter list). 203 candidates went
  (ISP company websites, domains that changed hands, empty web hosting);
  416 were left (415 since one more moved to the starter list). Also: a
  type a test finds is now saved by itself, so a
  candidate that is dropped does not stay behind as a copy.
- What it means: that page is a list of ISPs, not of media servers. More
  to watch will not come from a longer list but from reading the media
  websites the ISPs' pages point to (point 4). Most linked from the pages
  that answered: DhakaFlix (24 pages), ICC (13), CircleFTP's new site (8),
  moviemazic.xyz (7), CTGMovies, MovieHaat, FlixHub and Discovery FTP (5
  or 6 each), DhakaMovie, TimepassBD and eBox (4 each).
- Open: a second test run at another time of day, to see which of the 314
  silent candidates and the 15 silent starter servers answer then; taking
  in the servers the ISPs' pages link to that no list has yet.

### 4. Custom websites

- 20 of the 38 starter servers were custom websites without an adapter;
  18 of 51 are since 2026-11-20.
- Cost per site: saved sample pages, a parser of a few hundred lines, tests.
  The installed app barely grows; the codebase and the upkeep do (a site
  that changes its pages breaks its adapter). A site that only works by
  running JavaScript or after a login stays out (no WebView).
- Proposed: not all of them. After the longer list is tested, pick the few
  with the most content that is not already readable through a file server.
- Looked at on 2026-11-20, one front page each and a page or two more where
  it helped. No adapter was needed for the first three:
  - **CircleFTP** (new site, Circle HD): the films lie on its h5ai file
    servers. Twelve more of those are in the starter list now, so the two
    websites need no adapter.
  - **AmaderFTP**: an IIS server that lists its own folders. Read as that.
  - **Ctgstream**: Emby with a password-less user. Read as that.
  - **CTGMovies**: a Next.js app; its file server is in the starter list.
  - **FlixHub**: the first adapter, written on 2026-11-21
    (`FlixHubAdapter`). The film list comes a page at a time as JSON
    (`/movies?page=N`, 68 pages), every show's episodes are on its one
    page, and a video is one address (`/stream/movie/<name>`,
    `/stream/episode/<name>`) that answers with ranges and without
    signing in. Read from the real site: 1,897 films, 115 shows. Left out:
    subtitles (the site lists them per video, a request each) and the
    kids' section (it asks to sign in). Not yet tried: indexing and
    playing in the app.
  - **Khulnaplex**: the second adapter, written on 2026-11-21
    (`KhulnaplexAdapter`). Lists on numbered pages; a film or an episode
    is a plain file of the site, but its address stands only on a page of
    its own and the folders cannot be listed, so each costs a request
    (about 2,500 for a first crawl; later crawls read only the lists and
    the shows). Read from the real site: 1,252 films, 113 shows. Not yet
    tried: indexing and playing in the app.
  - **Elaach** (a candidate): films are plain mp4 files on
    `content.elaach.com`, which did not answer from this connection.
  - **NowHDTime** (behind Cloudflare, with accounts), **SunPlex**
    (WordPress with a sign-in form), **MojaLoss** (membership): not looked
    into further; likely to need an account, which the app does not do.
  - **FastPlex**, **Halum**, CTG Hub (a candidate): front pages that only
    link to other servers. No adapter can read them.
  - Did not answer that night, so not looked at: DFLIX, iHub, NaturalBD,
    MovieHaat, Funtime, FTPmedia, Radiant, Relax Time.
- Next: after a test run at another time of day, look at DFLIX and
  MovieHaat (among the most linked), then write the first adapter.

### 5. Renewing the libmpv pin

- Done on 2026-11-20: `tool/update-libmpv.ps1`, one command that finds the
  newest build, downloads it, checks the published SHA-256, rewrites
  `windows/libmpv.cmake`, `tool/bundled-libraries.sha256` and the build's
  name in the docs, builds, and runs the real-libmpv tests. Tried in a copy
  of the repository up to the rewriting; the build and test part has not
  run yet (the pinned build was the newest).
- Still open: a monthly job that does the same and opens a pull request,
  possible once there is CI.

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
- Done on 2026-11-21: Server Discovery has a search field.
- More versions of the logo to choose from (`lib/widgets/logo.dart`): a
  darker one, one with rounded corners on the play triangle and a changed
  wave under it, and a few more. Six were shown on 2026-11-20 (A is the
  logo as it is; B dark with a coloured mark; C rounded play and two waves;
  D deeper gradient and a longer wave; E dark with a stream of three waves;
  F the play over filled water). Chosen on 2026-11-20: **F** is the logo
  and the app's icon; A, B and C stay in the code as `DharaLogoStyle`
  (`classic`, `dark`, `rounded`) for later use, and so do the two shown
  after them: B with a rounded play triangle (`darkRounded`) and a dark F
  (`darkWater`).

## Later on 2026-11-21

- **Corrections.** `index.circleftp.net` is not dead: its folder
  `/FILE/` answers (9,304 videos), only its front page passed on to an
  error page that night. It is the 52nd server of the starter list, under
  the id the user's own entry has, so the two do not read it twice. And the
  user's entry was never taken out of the saved list: what a session's
  shell writes into `%APPDATA%` goes to a copy of its own, not to the
  real file. A session cannot change the saved source list; the app can.
- **The folders with `&` or `+` in their names** cannot be read by
  writing the address another way: every spelling tried was refused, and
  the website itself does not link to those films. Only whoever runs the
  server can mend it, by renaming the folders.
- **`library.db`**: schema version 5, 768 MB to 465 MB on a copy of the
  real library (see "Library database" in DEVELOPMENT.md). An installed
  1.0.2 refuses a version 5 library and leaves it alone, so it can no
  longer throw away what a newer build indexed, but it also shows no
  library until it is replaced by a new installer.
- **The logo** can be chosen in Settings, from the six drawings. Since
  1.0.3 the app starts with "Dark water" (F2), which is also the icon, and
  an installer can be made to start with another (`tool/package.ps1 -Logo`
  or `-LogoFromSettings`).
- **Short addresses** (schema 6): 476 MB to 406 MB on a copy of the real
  library.
- **Version 1.0.3**, the first installer with all of the above. Like the
  ones before it, made on the PC that is still to be reset.

## Found on 2026-11-21, after the user indexed the new servers

About 300,000 videos were in the library (Ctgstream 82,000, CTGMovies media
47,000, AmaderFTP 8,800).

- **An older build throws away what a newer one indexed.** The saved
  `sources.json` held test results for the 38 servers of 1.0.2 only and no
  `types`, and the library no longer had CTGMovies media: the installed
  1.0.2 had been opened after the development build. It forgets servers its
  own list does not know, their index with them
  (`IndexStore.removeSourcesExcept`). Until the installed app is as new as
  the list, only one of the two should be opened; a new installer ends it.
- **What "N folders could not be read" means.** Nothing the app can mend:
  folders whose names hold `&` (IIS answers 400) or `+` (404) however the
  address is written, folders behind a password (401), and the h5ai
  software's own folders (`_h5ai`, "not a folder listing"). 68 of 8,912
  folders on AmaderFTP, a handful elsewhere. Could be done: not following
  `_h5ai`, and saying this in calmer words than a warning.
- **Why `library.db` is 725 MB.** 260 MB of it is free space left by the
  index that was thrown away; SQLite keeps it for later and nothing gives
  it back. The rest, about 465 MB: cached TMDB answers 103 MB (88,000),
  the videos 74 MB and a second copy of their addresses for looking up
  what was watched 54 MB (an address is 155 characters on average), the
  search index over names 66 MB, episodes 31 MB, titles 29 MB, folders
  37 MB. Could be done, cheapest first: give free space back when there is
  much of it (`VACUUM`); drop cached search answers of titles that are
  matched; keep a video's address as its folder plus its name.
- The user's own "CircleFTP Index1" (`index.circleftp.net`) was no copy of
  the new `index1` entry: it passes on to CircleFTP's error page. Taken out
  of the saved list at the user's word.
- DFLIX, DhakaFlix and MovieHaat still did not answer from the user's
  connection.

## Still open from before

- The PC is to be reset; installers are made again and the TMDB key is
  replaced after that.
- The 4K film took 7.5 s to start (13 copies asked, 2 answered).
- Poster cards without a hover effect for a while, once, on a second PC.
- "No other copy answers." once or twice on Switch server.
