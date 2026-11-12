# Sample folder pages

Saved answers the adapter tests run against, so the tests work without any
BDIX connection.

Captured unchanged from servers in the starter list (2026-11-12, one page
each):

| File | Server software | From |
|---|---|---|
| `apache_table_folders.html` | Apache, table layout, ISO dates | ICC FTP `10.16.100.202` |
| `apache_table_file.html` | Apache, table layout, a file with a size | ICC FTP `10.16.100.202` |
| `apache_table_named_months.html` | Apache 2.2, `01-Aug-2022` dates | Xplex `172.27.27.124` |
| `iis_links_only.html` | IIS, customised: links without dates or sizes | ICC FTP `10.16.100.241` |
| `h5ai_root.html` | h5ai 0.29.0 | DhakaFlix 7 `172.16.50.7` |
| `h5ai_files.html` | h5ai 0.29.0, files with sizes | DhakaFlix 7 `172.16.50.7` |
| `h5ai_0_29_2.html` | h5ai 0.29.2 | CircleFTP `index2.circleftp.net` |

Written by hand, in the format the server software documents, because no
reachable server produced them. Titles are made up:

| File | Format |
|---|---|
| `nginx_autoindex.html` | nginx `autoindex on` |
| `iis_with_details.html` | IIS directory browsing with date and size |
| `apache_plain.html` | Apache without `HTMLTable` (a `<pre>` block) |
| `not_a_listing.html` | an ordinary web page, which must be refused |

The Emby/Jellyfin samples are in `test/fixtures/emby`.
