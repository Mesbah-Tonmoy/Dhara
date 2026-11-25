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

## ৬. App-এর ভেতর থেকে update

এটা test copy ("Dhara Test") দিয়ে দেখুন, যাতে আসল app আর আসল library-তে হাত
না পড়ে। Test-এর জন্য আলাদা একটা key বানান; আসল key দিয়ে test installer sign
করবেন না।

প্রস্তুতি (একবার):

1. Test key বানান:

   ```powershell
   pwsh tool/sign-update.ps1 -NewKey D:\keys\dhara-update-test
   ```

2. Google Drive-এ `dhara-update.json` নামে যেকোনো ছোট একটা file তুলুন,
   "anyone with the link" share করুন, link copy করুন। এটা notice-এর link।
3. Test installer বানান:

   ```powershell
   pwsh tool/package.ps1 -TestDataDir D:\tmp\dhara-update -UpdateUrl "<notice-এর link>" -UpdateKeyFile D:\keys\dhara-update-test.public.txt
   ```

4. `dist\Dhara-Test-Setup-<version>.exe` Drive-এ তুলুন, share করুন, link copy
   করুন। এখন আপনার হাতে দুটো link: ২ নম্বর ধাপের notice-এর link আর এই
   installer-এর link। Sign করার সময় `-InstallerLink`-এ **installer-এর**
   link দিন, notice-এর নয়। সেটাকে একটা উঁচু version বলে sign করুন (হলুদ
   একটা লাইন বলবে installer-এর নিজের version আলাদা; test-এ সেটাই চাই):

   ```powershell
   pwsh tool/sign-update.ps1 -Installer dist\Dhara-Test-Setup-<version>.exe -InstallerLink "<installer-এর link>" -KeyFile D:\keys\dhara-update-test.private.pem -Version 9.9.9 -Notes "Test update."
   ```

   Script আগে link-এ যা আছে তা নামিয়ে installer-এর সাথে মিলিয়ে দেখে, আর
   "It is this installer." বলে তবেই sign করে। ভুল link দিলে বলে সেখানে কী
   পেয়েছে, আর কিছু লেখে না।

5. Drive-এ notice file-এ right-click, "File information", "Manage versions",
   "Upload new version" দিয়ে `dist\dhara-update.json` তুলুন। আগে জানা
   notice app মনে রাখে, তাই নতুনটা পেতে Settings-এ **Check now** চাপুন।

পরীক্ষা:

1. `dist\Dhara-Test-Setup-<version>.exe` চালিয়ে "Dhara Test" খুলুন। আধা
   মিনিট পরে title bar-এ নামের পাশে **Update** আসবে। (না এলে Settings,
   Privacy and security, Updates-এ **Check now** চাপুন; সেখানে লেখা থাকবে
   "Version 9.9.9 is available"।)
2. এ পর্যন্ত কিছু নামেনি: `D:\tmp\dhara-update\update` folder নেই বা খালি।
3. **Update** চাপুন। Dialog-এ version, installer-এর আকার, "Test update." আর
   কী ঘটবে তা লেখা থাকবে। **Later** চাপলে কিছুই হবে না।
4. আবার খুলে **Download and install** চাপুন: bar ভরবে ("… of … MB"), তারপর
   "Checking…", তারপর installer-এর window খুলবে আর Dhara Test নিজে বন্ধ হবে।
   Admin prompt আসার কথা নয়।
5. Installer শেষ করুন, শেষ পাতা থেকে Dhara Test আবার খুলুন: library আর
   settings আগের মতোই আছে। (এটা একই version আবার বসাল, তাই **Update** আবার
   দেখাবে; আসল release-এ নতুন version বসার পরে আর দেখায় না।)
6. ভুল file ধরা পড়ে কি না: Drive-এ installer file-এ "Manage versions" দিয়ে
   অন্য যেকোনো file তুলুন। **Download and install** চাপুন: dialog বলবে "What
   came is not the installer its maker signed…", কোনো installer খুলবে না, আর
   `D:\tmp\dhara-update\update` খালি থাকবে।
7. নামানোর মাঝখানে **Stop** চাপুন: dialog আগের অবস্থায় ফিরবে, folder খালি।
8. Internet বন্ধ করে **Check now** চাপুন: "did not answer" লেখা আসবে, আর
   আগে জানা version-এর কথা থেকে যাবে।
9. Development build-এ (`flutter run -d windows`) Settings-এর Updates সারিতে
   "MANUAL" লেখা, **Check now** নেই, title bar-এ **Update** নেই।
10. শেষে "Dhara Test" uninstall করুন, `D:\tmp\dhara-update` folder আর
    Drive-এর test file দুটো মুছে দিন। Test key আর কোথাও ব্যবহার করবেন না।

আসল release-এ একই ধাপ, শুধু `-TestDataDir` আর `-Version` ছাড়া, আসল key
দিয়ে: README-র "নিজে build করা" অংশে লেখা আছে।

## কিছু না মিললে

কোন ধাপে কী দেখলেন লিখে রাখুন, আর player-এর সমস্যা হলে **I** panel-এ যা
লেখা ছিল সেটাও। Installer আবার বানাতে (link আর key-র file নিজের মতো
দিন; key-র file repository-র বাইরে থাকতে হবে):

```powershell
pwsh tool/package.ps1 -SnapshotUrl "<Drive link>" -TmdbKeyFile D:\keys\dhara-tmdb.txt
```
