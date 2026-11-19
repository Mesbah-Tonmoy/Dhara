# Dhara

**[Read this in English](README.md)**

Dhara একটা Windows desktop app। BDIX media server-গুলোতে যে film, series
আর anime আছে, সেগুলোকে এটা একটাই library বানিয়ে দেখায়। আপনার connection
থেকে যে server-গুলো পাওয়া যায় সেগুলোতে কী আছে তা খুঁজে বের করে, প্রতিটা
title-কে poster আর নিজের একটা page দেয়, আর যে server সবচেয়ে তাড়াতাড়ি
সাড়া দেয় সেখান থেকে চালায়।

এটা একজনের নিজের ব্যবহারের জন্য বানানো, আর Kodi বা Infuse-এর মতো এটা
**শুধুই একটা client**: নিজে কিছু host করে না, কিছু share করে না; এতে
account, বিজ্ঞাপন বা telemetry নেই।

## কী কী করে

- **অনেক server, একটা library।** App-এর সাথে হাতে যাচাই করা ৩৯টা BDIX
  server-এর একটা তালিকা আসে, সাথে একটা public তালিকা থেকে নেওয়া আরও
  প্রায় ৪০০টা, যেগুলো এখনো কেউ নিশ্চিত করেনি; app পরীক্ষা করে দেখে আপনার connection থেকে কোনগুলো সাড়া
  দেয়। এটা folder listing (Apache, nginx, IIS), h5ai page আর Emby/Jellyfin
  server পড়তে পারে। একই film কয়েকটা server-এ থাকলে সেটা একটাই title,
  যার কয়েকটা copy।
- **লিখতে লিখতেই search**, সাথে type, quality, rating, বছর আর genre-এর
  filter। Library আপনার PC-তেই রাখা থাকে, তাই search-এর সময় কোনো server-কে
  জিজ্ঞেস করতে হয় না।
- **Poster, বিবরণ, cast আর episode-এর নাম** আসে TMDB থেকে, আপনার নিজের
  key দিয়ে। Anime page-এ AniList-এর seasonal আর trending তালিকাও থাকে।
- **Player app-এর ভেতরেই আছে** (libmpv): VLC বা codec pack লাগে না। MKV,
  MP4 আর অন্য প্রচলিত file চলে; styled আর ছবি-ভিত্তিক subtitle, একাধিক
  audio track আর hardware decoding আছে।
- **Play শুরু হয় সবচেয়ে দ্রুত copy থেকে**, আপনার পছন্দের quality-তে।
  কোনো server আটকে গেলে video একই জায়গা থেকে অন্য copy-তে চলতে থাকে।
- **Resume, countdown সহ পরের episode, My List আর History।**
- **নিজের মতো seek step:** পেছনে আর সামনে যাওয়ার আলাদা মান, যা button
  আর arrow key দুটোই ব্যবহার করে।
- **সব কাজ keyboard দিয়েই করা যায়।**

## Install

Dhara-র জন্য Windows 10 বা 11 (64-bit) লাগে। Player সহ আর যা কিছু দরকার,
সব app-এর সাথেই আসে।

1. `Dhara-Setup-<version>.exe` চালান। এটা কোথাও প্রকাশ করা হয় না: এই
   repository থেকে বানাতে হয় ([নিজে build করা](#নিজে-build-করা) দেখুন),
   আর বানানোর পরে `dist\` folder-এ থাকে।
2. Installer-এর কোনো copy সত্যিই বানানো file-টাই কি না দেখতে তার SHA-256
   মিলিয়ে নিন পাশের `.sha256` file-এর মানের সাথে:

   ```powershell
   (Get-FileHash dist\Dhara-Setup-*.exe -Algorithm SHA256).Hash
   ```

Installer app-টা `%LOCALAPPDATA%\Programs\Dhara`-তে বসায় আর Start Menu-তে
একটা shortcut দেয় (tick দিলে desktop-এও)। এটা শুধু আপনার user-এর জন্য
install করে, admin rights চায় না। কোনো service, start-up entry বা updater
যোগ করে না। নতুন version বসাতে তার installer চালালেই হয়; পুরনোটার উপরে
বসে যায়।

## প্রথমবার যা করতে হবে

Library-তে কিছু না আসা পর্যন্ত Home এই তিনটা ধাপ দেখায়, আর কোনটা কতদূর
হয়েছে তাও বলে।

1. **Server।** Rail থেকে Server Discovery খুলুন, **Test all** চাপুন,
   তারপর **Enable all reachable**। অনেক BDIX server শুধু নির্দিষ্ট ISP
   থেকেই সাড়া দেয়, তাই আপনার connection যেগুলো পায় শুধু সেগুলোই চালু হয়।
2. **Index।** Settings থেকে **Library index** খুলে **Update index** চাপুন।
   App চালু করা server-গুলোর folder পড়ে নেয়; তিনটা server-এ প্রথমবার ১৫
   থেকে ২০ মিনিট লেগেছিল। পরের বার অনেক কম সময় লাগে, আর app নিজেই করে
   নেয়, দিনে বড়জোর একবার।
3. **Poster।** Settings থেকে **Titles and matching** খুলে আপনার TMDB key
   দিন (TMDB account-এর *API Read Access Token*), তারপর **Match now**
   চাপুন। Key না দিলেও বাকি সব চলে; তখন poster-এর জায়গায় আঁকা একটা ছবি
   থাকে।

এসব ছাড়াও একটা video সরাসরি চালানো যায়: Ctrl+O চেপে তার `http://` ঠিকানা
paste করুন।

## Keyboard

App-এ:

| Key | কী করে |
|---|---|
| Ctrl+K বা / | Search field-এ যায় |
| Search field-এ Enter বা ↓ | প্রথম result-এ যায় |
| Ctrl+O | Play a URL |
| Alt+←, mouse-এর back button | পেছনে যায় |
| Esc | Text field ছাড়ে বা dialog বন্ধ করে, নইলে পেছনে যায় |
| Tab, arrow key, Enter বা Space | Button, card আর সারির মধ্যে চলাফেরা করে, আর চাপে |
| Page Up, Page Down, Home, End | Page scroll করে |

Player-এ:

| Key | কী করে |
|---|---|
| Space | Play বা pause |
| ← আর → | আপনার seek step অনুযায়ী পেছনে বা সামনে যায় |
| ↑ আর ↓ | Volume বাড়ায় বা কমায় |
| M | Mute |
| S | পরের subtitle track |
| F, বা double-click | Fullscreen |
| N | পরের video |
| I | Playback info: server, গতি, buffer, decoder |
| Esc | খোলা panel বন্ধ করে, তারপর fullscreen ছাড়ে, তারপর player থেকে বের হয় |

## আপনার data

App যা কিছু রাখে, সব এই PC-তেই থাকে:

| কী | কোথায় |
|---|---|
| Library, My List, history আর কোন video কোথায় থেমেছিল | `%APPDATA%\com.dhara\dhara\library.db` |
| Settings আর server তালিকায় আপনার পরিবর্তন | একই folder-এর `shared_preferences.json` আর `sources.json` |
| Download করা poster (সর্বোচ্চ ৩০০ MB) | একই folder-এর `images` |
| TMDB key | Windows Credential Manager, `Dhara/tmdb` নামে |

App যোগাযোগ করে আপনার চালু করা server-গুলোর সাথে, "Play a URL"-এ আপনি
যে ঠিকানা paste করেন তার সাথে, TMDB-র সাথে (শুধু key থাকলে; title আর বছর
পাঠানো হয়) আর AniList-এর সাথে (Anime page খুললে; আপনার library-র কিছুই
পাঠানো হয় না)। এর বাইরে কারো সাথে যোগাযোগ করে না, আর কোনো log লেখে না।

## সরিয়ে ফেলা

Windows Settings, Apps থেকে Dhara uninstall করুন। এতে app আর তার shortcut
মুছে যায়, আপনার data থেকে যায়। Data-ও মুছতে চাইলে:

- `%APPDATA%\com.dhara\dhara` folder-টা মুছে দিন
- Control Panel, Credential Manager, Windows Credentials থেকে `Dhara/tmdb`
  সরিয়ে দিন

## নিরাপত্তা

Server-গুলোকে বিশ্বাস করা হয় না। তারা যা পাঠায় তা শুধু parse করা হয়, কখনো
render বা run করা হয় না। আর player কিছু খোলার আগেই তাকে বেঁধে দেওয়া হয়:
script নেই, yt-dlp নেই, configuration file নেই, আর network protocol শুধু
`http` আর `https`। প্রতিটা নিয়ম ধরে ধরে পুরো review আছে
[docs/security-review.md](docs/security-review.md)-তে (English)।

ক্ষতিকর file আক্রমণ করলে player-এই করবে। তাই media_kit-এর সাথে যে libmpv
আসে (September 2023-এর build, যাতে নতুন কোনো fix আসে না), app সেটা ব্যবহার
করে না; তার জায়গায় চলতি একটা build দেয় (November 2026-এর mpv 0.42)। তবে
এটা ততদিনই ঠিক থাকে যতদিন নতুন build নেওয়া হয়: নিচে
[Player আপডেট রাখা](#player-আপডেট-রাখা) দেখুন।

## Player আপডেট রাখা

যে dependency-র দিকে সবচেয়ে বেশি নজর রাখা দরকার, সেটা player-এর library।
এটা app-এ ঢোকে এভাবে:

- `pubspec.yaml`-এ `media_kit`, `media_kit_video` আর
  `media_kit_libs_windows_video`-এর version pin করা। media_kit libmpv-কে
  চালায়; সে নিজে যে libmpv সাথে আনে সেটা ২০২৩-এর, আর সেটা app-এ রাখা হয় না।
- `windows/libmpv.cmake`-এ libmpv-র একটা নির্দিষ্ট build লেখা আছে: mpv.io
  যে Windows build-গুলোর তালিকা দেয় তার একটা archive (GitHub-এর
  `shinchiro/mpv-winbuild-cmake`), তার ঠিকানা আর তার SHA-256। App build
  করার সময় ওই archive একবার download হয়, `windows/libmpv/`-এ রাখা হয়
  (git-এ নয়), SHA-256 মিললে তবেই ব্যবহার হয়, আর তার ভেতরের `libmpv-2.dll`
  app-এর পাশে বসে। App ওই file-টাকেই তার পুরো path ধরে load করে, অন্য
  কোনোটা নয়।
- `tool/bundled-libraries.sha256`-এ ওই `libmpv-2.dll`-এর SHA-256 লেখা আছে,
  আর `tool/package.ps1` অন্য কোনো file দিয়ে installer বানায় না।

কোনো build-এ কোন libmpv আছে দেখতে file-টার version stamp দেখুন (এখন
`v0.42.0-38-gbcde6b93c`):

```powershell
(Get-Item dist\Dhara-*\libmpv-2.dll).VersionInfo.ProductVersion
```

**এক-দুই মাস পরপর, আর প্রতিটা নতুন installer বানানোর আগে, সবচেয়ে নতুন
build-টা নিন:**

1. `pwsh tool/update-libmpv.ps1` চালান (`-Check` দিলে শুধু বলে নতুন build
   আছে কি না)। এটা <https://github.com/shinchiro/mpv-winbuild-cmake/releases>
   থেকে সবচেয়ে নতুন `mpv-dev-x86_64-<date>-git-<hash>.7z` খুঁজে নেয়
   (`v3` লেখাটা নয়; ওটা শুধু নতুন processor-এ চলে), download করে, আর
   GitHub তার পাশে যে SHA-256 দেখায় সেটার সাথে মিললে তবেই এগোয়। তারপর
   `windows/libmpv.cmake`-এর তিনটা মান (file-এর নাম, ঠিকানার ভেতরের তারিখ,
   SHA-256), `tool/bundled-libraries.sha256`-এ `libmpv-2.dll`-এর লাইন, আর
   এই file ও [docs/security-review.md](docs/security-review.md)-র table-এ
   build-এর নাম লিখে দেয়।
2. এরপর এটা `flutter build windows --release` আর আসল `libmpv-2.dll`
   চালানো test-গুলো চালায়: প্রতিটা hardening option বসিয়ে আবার পড়ে মেলায়,
   mpv নিজে থেকে যে script চালু করে তার সবগুলো বন্ধ কি না দেখে, redirect
   মানা হয় না তা দেখে, video-র জায়গায় পাঠানো playlist এই PC-র কোনো file
   খুলতে পারে না তা দেখে, আর একটা local web server থেকে video চালায়।
   এখানে কোনো test fail করা মানে কোনো option-এর নাম বা অর্থ বদলেছে, অথবা
   mpv নিজে থেকে নতুন কিছু করতে শুরু করেছে। কারণটা না বোঝা পর্যন্ত আর
   এগোবেন না; পুরনো pin-এ কীভাবে ফিরবেন script-ই বলে দেয়।
3. পুরো `flutter test` চালান, আর `git diff` দেখে নিন।
4. `pwsh tool/package.ps1` চালান, যা তৈরি হয় সেটা install করে
   [docs/manual-test.bn.md](docs/manual-test.bn.md) ধরে দেখে নিন: একটা
   film, seek, subtitle, দ্বিতীয় audio track, episode-এর শেষ, আর info
   panel-এর (I key) decoder লাইন।
5. Commit করুন। Script নিজে কিছু commit করে না।

Script-টা ২০২৬-১১-২০ তারিখে repository-র একটা copy-তে চালিয়ে দেখা হয়েছে,
যেখানে একটা পুরনো build pin করা ছিল: এটা ২০২৬-১১-১১-র build নিয়েছে আর
file-গুলো ঠিক এখানকার মতোই লিখেছে। এর শেষ অংশ, build আর test, এখনো চলেনি,
কারণ নেওয়ার মতো নতুন build ছিল না।

এর চেয়ে বেশি দেরি করবেন না। ২০২৬-১১-১৮ তারিখে ওই উৎস তার শেষ ৩০টা build
রাখছিল, যার সবচেয়ে পুরনোটা ছয় সপ্তাহেরও কম আগের। Pin করা build-টা ওখান
থেকে সরে গেলে, যে PC-র `windows/libmpv/`-এ archive-টা নেই সেখানে নতুন build
pin না করা পর্যন্ত app আর build হবে না।

মাঝে মাঝে `flutter pub outdated`-ও চালিয়ে media_kit-এর তিনটা package দেখুন।
কোনোটার নতুন version থাকলে তার changelog পড়ুন, `pubspec.yaml`-এ তিনটার
version একসাথে বাড়ান, build করুন, আর ধাপ ৩ ও ৪ করুন।

**প্রথমবার build বদলাতে যা লেগেছে (২০২৬-১১-১৮)।** mpv 0.42-এ এমন কিছু
জিনিস আছে যা ২০২৩-এর build-এ ছিল না, আর app ছাড়ার আগে সেগুলো বন্ধ করতে
হয়েছে: Lua script, যা mpv নিজে থেকেই চালু করে (তার একটা `yt-dlp` চালানোর
hook), আর একটা libcurl, যা protocol whitelist এড়িয়ে `http` ঠিকানা খোলে। কী
করা হয়েছে তা security review-র finding 11 আর 12-তে লেখা। আরও নতুন build
এ ধরনের আরও কিছু আনতে পারে; ধাপ ৩-এর test-গুলো সেটা ধরার জন্যই।

**এটা দিয়ে যা পরীক্ষা হয়েছে:** সব automated test, আর চালু app-এ এই PC-র
একটা web server থেকে একটা video, যেটা hardware decoding দিয়ে চলেছে আর
তাতে seek করা গেছে। **এখনো পরীক্ষা হয়নি:** আসল BDIX server, একাধিক audio
track বা subtitle-ওয়ালা file, Dolby TrueHD track (এই build-এ তার decoder
আছে, পুরনোটায় ছিল না) আর `https` server।

## নিজে build করা

লাগবে Flutter (stable channel), Visual Studio 2022 Build Tools (সাথে
*Desktop development with C++* workload) আর Windows Developer Mode।

```powershell
flutter pub get
flutter analyze
flutter test
flutter run -d windows --release
```

Installer বানাতে আরও লাগবে
[Inno Setup 6](https://jrsoftware.org/isinfo.php)
(`winget install --id JRSoftware.InnoSetup -e`):

```powershell
pwsh tool/package.ps1
```

Script-টা release build করে, সাথে দেওয়া প্রতিটা library-কে
`tool/bundled-libraries.sha256`-এর SHA-256 তালিকার সাথে মেলায়, আর installer
ও তার checksum `dist\`-এ লেখে। যে PC-তে installer বানানো হয়, installer-কে
ততটুকুই বিশ্বাস করা যায় যতটুকু সেই PC-কে।

## মাপা সংখ্যা

যে PC-র জন্য app বানানো (Ryzen 5 5500U, integrated graphics, Windows 11),
২৩,৩৮৯টা video-র library:

| | লক্ষ্য | মাপ |
|---|---|---|
| Cold start | ২ s-এর কম | 0.85 থেকে 0.9 s |
| Search | ১০০ ms-এর কম | title দিয়ে 2 থেকে 7 ms |
| Playback শুরু | ২ s-এর কম | আসল BDIX server-এ 0.7 থেকে 1.8 s |
| Installer | বড়জোর ~80 MB | 48.2 MB (app-এর file-গুলো: 167 MB) |
| Idle memory | | Home-এ 196 থেকে 210 MB working set |

## যা এখনো পারে না

- তালিকার ৩৯টা server-এর ২০টা নিজস্ব ধরনের website। App এগুলো পরীক্ষা
  করতে পারে, কিন্তু পড়তে পারে না।
- Self-signed certificate-এর `https` server-এ app যুক্ত হয় না।
- App শুধু Windows-এ build আর পরীক্ষা করা হয়েছে।

## আরও পড়তে চাইলে

প্রথমটা বাদে নিচের file-গুলো English-এ লেখা।

- [docs/manual-test.bn.md](docs/manual-test.bn.md): নতুন installer বানানোর
  পরে নিজে যা পরীক্ষা করবেন
- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): প্রতিটা অংশ কীভাবে কাজ করে,
  কী মাপা আর পরীক্ষা করা হয়েছে, আর কোন ফাঁক জানা আছে
- [docs/security-review.md](docs/security-review.md): security review
- [assets/sources/README.md](assets/sources/README.md): server তালিকার
  format
- [BRIEF.md](BRIEF.md): যে brief থেকে app বানানো হয়েছে

This product uses the TMDB API but is not endorsed or certified by TMDB.
