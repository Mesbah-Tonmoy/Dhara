# নতুন installer নিজে পরীক্ষা করার তালিকা

নতুন installer বানানোর পরে এই তালিকা ধরে একবার দেখে নিন: PC reset-এর পরে,
নতুন version-এ, বা media_kit/libmpv বদলানোর পরে। BDIX server শুধু
বাংলাদেশের ISP থেকে পাওয়া যায়, তাই এই পরীক্ষাগুলো automated test দিয়ে হয়
না; নিজের PC-তেই করতে হয়।

## ১. Installer

1. Checksum মেলান। নিচের command-এর ফল `dist\Dhara-Setup-1.0.1.exe.sha256`
   file-এর মানের সাথে মিলতে হবে:

   ```powershell
   (Get-FileHash dist\Dhara-Setup-1.0.1.exe -Algorithm SHA256).Hash
   ```

2. `dist\Dhara-Setup-1.0.1.exe` চালান। Admin prompt আসার কথা নয়, আর
   install-এর folder বেছে নিতে বলার কথা নয়।
3. Start Menu-তে "Dhara" আছে, আর app বসেছে
   `%LOCALAPPDATA%\Programs\Dhara`-তে।
4. Start Menu থেকে Dhara খুলুন। আগে ব্যবহার করে থাকলে library, settings,
   My List আর History আগের মতোই থাকবে।
5. Taskbar-এ আর window-এর title-এ app-এর নিজের icon আর "Dhara" নাম আছে;
   Settings-এ version 1.0.1।

## ২. Server আর library

1. Server Discovery খুলে **Test all** চাপুন: আপনার connection থেকে যে
   server-গুলো পাওয়া যায় সেগুলো reachable দেখাবে।
2. Settings, **Library index**, **Update index**: progress দেখাবে আর শেষ
   হবে।
3. Ctrl+K চেপে একটা film-এর নাম লিখুন: লিখতে লিখতেই result আসবে।
4. Home-এ উপরে-নিচে জোরে scroll করুন: আটকাবে না, আর banner-এর ছবি
   banner-এর বাইরে বের হবে না।

## ৩. Player

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

## ৪. Uninstall

1. Windows Settings, Apps থেকে Dhara uninstall করুন: Start Menu-র shortcut
   আর `%LOCALAPPDATA%\Programs\Dhara` folder চলে যাবে।
2. `%APPDATA%\com.dhara\dhara` folder থেকে যাবে। আবার install করলে library
   আগের মতোই ফিরে আসবে।

## কিছু না মিললে

কোন ধাপে কী দেখলেন লিখে রাখুন, আর player-এর সমস্যা হলে **I** panel-এ যা
লেখা ছিল সেটাও। Installer আবার বানাতে:

```powershell
pwsh tool/package.ps1
```
