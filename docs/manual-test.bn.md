# নতুন installer নিজে পরীক্ষা করার তালিকা

নতুন installer বানানোর পরে এই তালিকা ধরে একবার দেখে নিন: PC reset-এর পরে,
নতুন version-এ, বা media_kit/libmpv বদলানোর পরে। BDIX server শুধু
বাংলাদেশের ISP থেকে পাওয়া যায়, তাই এই পরীক্ষাগুলো automated test দিয়ে হয়
না; নিজের PC-তেই করতে হয়।

## ১. Installer

1. Checksum মেলান। নিচের command-এর ফল `dist\Dhara-Setup-<version>.exe.sha256`
   file-এর মানের সাথে মিলতে হবে:

   ```powershell
   (Get-FileHash dist\Dhara-Setup-*.exe -Algorithm SHA256).Hash
   ```

2. `dist\Dhara-Setup-<version>.exe` চালান। Admin prompt আসার কথা নয়, আর
   install-এর folder বেছে নিতে বলার কথা নয়।
3. Start Menu-তে "Dhara" আছে, আর app বসেছে
   `%LOCALAPPDATA%\Programs\Dhara`-তে।
4. Start Menu থেকে Dhara খুলুন। আগে ব্যবহার করে থাকলে library, settings,
   My List আর History আগের মতোই থাকবে।
5. Taskbar-এ আর window-এর title-এ app-এর নিজের icon আর "Dhara" নাম আছে;
   Settings-এ installer-এর নামের version-টাই লেখা।

## ২. Production build-এর প্রথম start

Installer-এ থাকে production build। তার প্রথম start নিজের PC-তে আসল
library নষ্ট না করে দেখতে একটা test installer বানান: সেটা "Dhara Test"
নামে পাশে বসে আর নিজের folder-এ data রাখে।

```powershell
pwsh tool/package.ps1 -SnapshotUrl "<Drive link>" -TestDataDir D:\tmp\dhara-first-start
```

1. `dist\Dhara-Test-Setup-<version>.exe` চালিয়ে Start Menu থেকে "Dhara
   Test" খুলুন। কিছু টিপবেন না।
2. Home-এ "Getting your library ready" দেখাবে: আগে "Fetching the library
   … MB", তারপর "Putting the library in place … %"। Title bar-এ নামের পাশে
   ছোট একটা চিহ্ন একই কথা বলবে ("Getting ready 45%")।
3. কয়েক মিনিটের মধ্যে Home-এ banner আর সারি আসবে। Title bar-এর ডান দিকে
   কয়টা server online তা দেখাবে।
4. Home আসার ১৫ সেকেন্ড পরে নামের পাশের চিহ্নে "Reading servers 3/29"-এর
   মতো লেখা আসবে, সংখ্যা বাড়বে, আর শেষ হলে চিহ্নটা চলে যাবে। এই সময়ে
   film চালানো যাবে।
5. Rail-এ "Titles and matching" আর "Library index" নেই; Settings-এ
   "Library and metadata" অংশ নেই। Server Discovery আছে।
6. Key দিয়ে বানানো installer হলে (`-TmdbKeyFile`): নতুন পাওয়া title-এ
   poster আসবে, আর চিহ্নে "Finding posters" দেখা যাবে। Settings-এ key
   কোথাও দেখানো হবে না।
7. App বন্ধ করে আবার খুলুন: Home সাথে সাথে আসবে, আবার কিছু নামাবে না।
8. মাঝপথে কাটা পড়লে কী হয় দেখতে: `D:\tmp\dhara-first-start` folder মুছে
   আবার খুলুন, "Putting the library in place" চলার সময় app বন্ধ করে দিন,
   তারপর আবার খুলুন। Window খুলতে একটু দেরি হবে, তারপর শুরু থেকে পড়ে শেষ
   করবে; আবার download করবে না।
9. Internet ছাড়া কী হয় দেখতে: folder-টা মুছে, internet বন্ধ রেখে খুলুন।
   Home বলবে "The library could not be fetched"। Internet চালু করে **Try
   again** চাপুন: library ভরে যাবে।
10. শেষে Windows Settings, Apps থেকে "Dhara Test" uninstall করুন আর
    `D:\tmp\dhara-first-start` folder মুছে দিন।

আসল installer (`-TestDataDir` ছাড়া) এমন PC-তে পরীক্ষা করুন যেখানে Dhara
আগে চলেনি: আপনার নিজের PC-তে library আগে থেকেই ভরা, তাই সেখানে production
build প্রথম start-এর কিছুই করে না, সরাসরি Home দেখায়।

## ৩. Development build: server আর library

এই ধাপগুলো `flutter run -d windows` বা `tool/package.ps1 -Dev`-এর
installer ("Dhara Dev") দিয়ে।

1. Server Discovery খুলে **Test all** চাপুন: আপনার connection থেকে যে
   server-গুলো পাওয়া যায় সেগুলো reachable দেখাবে।
2. Rail থেকে **Library index**, **Update index**: progress দেখাবে আর শেষ
   হবে।
3. **Write snapshot** চেপে একটা folder বাছুন: নিচে কত row লেখা হলো দেখাবে,
   শেষে file-এর আকার আর জায়গা। এই file-টাই Drive-এ তুলতে হয়
   ("Manage versions", "Upload new version" দিলে link একই থাকে)।
4. Ctrl+K চেপে একটা film-এর নাম লিখুন: লিখতে লিখতেই result আসবে।
5. Home-এ উপরে-নিচে জোরে scroll করুন: আটকাবে না, আর banner-এর ছবি
   banner-এর বাইরে বের হবে না।

## ৪. Player

1. একটা film-এ **Play** চাপুন: ২ সেকেন্ডের মধ্যে শুরু হওয়ার কথা।
2. **I** চাপুন: কোন server থেকে চলছে, কত সময়ে শুরু হলো, আর decoder-এর
   লাইনে graphics card decode করছে কি না দেখাবে।
3. → আর ← চাপুন, তারপর seek bar-এর মাঝখানে click করুন: ছবি তাড়াতাড়ি
   ফিরে আসবে।
4. Subtitle আছে এমন একটা film-এ **S** চাপুন: subtitle দেখা যাবে।
5. একাধিক ভাষার audio আছে এমন film-এ audio panel থেকে অন্য track বেছে
   নিন: শব্দ বদলাবে।
6. একাধিক copy আছে এমন film-এ **Switch server** চাপুন: একই জায়গা থেকে
   অন্য server-এ চলবে।
7. একটা episode-এর শেষ মিনিটে যান: "Up next" countdown আসবে, আর পরের
   episode নিজে থেকেই শুরু হবে।
8. মাঝপথে player বন্ধ করুন, app বন্ধ করে আবার খুলুন: Home-এর Continue
   Watching থেকে একই জায়গা থেকে চলবে।
9. History খুলুন: server বদলে দেখা film-টা একবারই আছে।

## ৫. Uninstall

1. Windows Settings, Apps থেকে Dhara uninstall করুন: Start Menu-র shortcut
   আর `%LOCALAPPDATA%\Programs\Dhara` folder চলে যাবে।
2. `%APPDATA%\com.dhara\dhara` folder থেকে যাবে। আবার install করলে library
   আগের মতোই ফিরে আসবে।

## কিছু না মিললে

কোন ধাপে কী দেখলেন লিখে রাখুন, আর player-এর সমস্যা হলে **I** panel-এ যা
লেখা ছিল সেটাও। Installer আবার বানাতে (link আর key-র file নিজের মতো
দিন; key-র file repository-র বাইরে থাকতে হবে):

```powershell
pwsh tool/package.ps1 -SnapshotUrl "<Drive link>" -TmdbKeyFile D:\keys\dhara-tmdb.txt
```
