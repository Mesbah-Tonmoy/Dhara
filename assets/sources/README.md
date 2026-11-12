# Starter source list

`starter_sources.json` is the list of BDIX media servers the app knows about
out of the box. It is data, not code: edit it freely. In the app, sources can
also be added, edited, disabled, removed, imported and exported.

Being in this list does **not** enable a server. The BDIX Tester checks each
one from your connection and only reachable servers are enabled.

## Schema (version 1)

```jsonc
{
  "schemaVersion": 1,          // bump when the shape changes
  "checkedOn": "YYYY-MM-DD",   // when the list was last checked by hand
  "sources": [
    {
      "id": "dhakaflix-7",     // unique, lower-case letters, digits and "-"
      "name": "DhakaFlix 7",   // shown in the app
      "provider": "DhakaFlix", // groups servers of one operator; may be null
      "isp": "SAM Online",     // ISP that runs it, if known; else null
      "type": "h5ai",          // see below
      "category": "movies",    // movies | series | anime | mixed
      "baseUrls": ["http://172.16.50.7/DHAKA-FLIX-7/"], // http/https, end in "/"
      "portalUrl": "http://172.16.50.4/",  // operator's landing page, or null
      "notes": "…"             // free text, or null
    }
  ]
}
```

| `type` | Meaning | Adapter |
|---|---|---|
| `directory_listing` | Plain web-server folder listing (Apache, nginx, IIS) | generic directory listing |
| `h5ai` | h5ai file index | h5ai |
| `emby` | Emby server | Emby / Jellyfin API |
| `jellyfin` | Jellyfin server | Emby / Jellyfin API |
| `custom_site` | A website with its own pages or API | one adapter per site, written when wanted |

A source may have several `baseUrls` (for example one per disk on the same
host). Each is crawled as its own root.

## How this list was built (2026-11-12)

1. Started from the servers already in use, and the servers their landing
   pages link to.
2. Merged two public "BDIX tester" lists:
   [0xAhmadYousuf/bdix `server.json`](https://github.com/0xAhmadYousuf/bdix)
   and
   [FakeErrorX/BDIX-FTP-TESTER `ftp_links.dart`](https://github.com/FakeErrorX/BDIX-FTP-TESTER)
   (both MIT). Together: 670 distinct URLs on 578 hosts.
3. Fetched each URL's front page once (short timeout, small size cap) from
   one Bangladeshi broadband connection. No port scanning and no address sweeps:
   only listed URLs, plus the folder links on the landing pages from step 1.
4. Kept only servers that answered **and** were recognisably media servers.

Not included, on purpose:

- 365 URLs that did not answer. Some may work on other ISPs; add them by
  hand or by import if you need them.
- ISP company websites that are not media servers.
- Domains that now point to gambling or spam sites, "for sale" pages and
  suspended accounts. Public lists are full of these, which is why the lists
  are not shipped as they are.
- Servers holding only games or software.
- 17 listed Emby/Jellyfin addresses (mostly port 8096): none answered.
