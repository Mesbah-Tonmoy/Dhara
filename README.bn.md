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

- **অনেক server, একটা library।** App-এর সাথে ৩৮টা BDIX server-এর একটা
  তালিকা আসে, আর app পরীক্ষা করে দেখে আপনার connection থেকে কোনগুলো সাড়া
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

1. `Dhara-Setup-1.0.0.exe` চালান। এটা কোথাও প্রকাশ করা হয় না: এই
   repository থেকে বানাতে হয় ([নিজে build করা](#নিজে-build-করা) দেখুন),
   আর বানানোর পরে `dist\` folder-এ থাকে।
2. Installer-এর কোনো copy সত্যিই বানানো file-টাই কি না দেখতে তার SHA-256
   মিলিয়ে নিন `Dhara-Setup-1.0.0.exe.sha256`-এর মানের সাথে:

   ```powershell
   (Get-FileHash Dhara-Setup-1.0.0.exe -Algorithm SHA256).Hash
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

জানা ঝুঁকির মধ্যে সবচেয়ে বড় হলো সাথে দেওয়া player-এর বয়স: libmpv 0.36 আর
FFmpeg 6.0, September 2023-এ বানানো। ক্ষতিকর file আক্রমণ করলে media
decoder-এই করবে, আর এই build-এ নতুন কোনো fix আসে না।

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
version 1.0.0, ২৩,৩৮৯টা video-র library:

| | লক্ষ্য | মাপ |
|---|---|---|
| Cold start | ২ s-এর কম | 0.85 থেকে 0.9 s |
| Search | ১০০ ms-এর কম | title দিয়ে 2 থেকে 7 ms |
| Playback শুরু | ২ s-এর কম | আসল BDIX server-এ 0.7 থেকে 1.8 s |
| Installer | বড়জোর ~80 MB | 24.9 MB (install-এর পরে 83.7 MB) |
| Idle memory | | Home-এ 213 থেকে 225 MB working set |

## যা এখনো পারে না

- তালিকার ৩৮টা server-এর ২০টা নিজস্ব ধরনের website। App এগুলো পরীক্ষা
  করতে পারে, কিন্তু পড়তে পারে না।
- Dolby TrueHD audio decode হয় না; player নিজে থেকেই file-এর অন্য একটা
  track-এ চলে যায়।
- Self-signed certificate-এর `https` server-এ app যুক্ত হয় না।
- App শুধু Windows-এ build আর পরীক্ষা করা হয়েছে।

## আরও পড়তে চাইলে

নিচের file-গুলো English-এ লেখা।

- [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md): প্রতিটা অংশ কীভাবে কাজ করে,
  কী মাপা আর পরীক্ষা করা হয়েছে, আর কোন ফাঁক জানা আছে
- [docs/security-review.md](docs/security-review.md): security review
- [assets/sources/README.md](assets/sources/README.md): server তালিকার
  format
- [BRIEF.md](BRIEF.md): যে brief থেকে app বানানো হয়েছে

This product uses the TMDB API but is not endorsed or certified by TMDB.
