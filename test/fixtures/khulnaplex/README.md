# Sample pages of Khulnaplex

Saved answers of `http://khulnaplex.net/` (2026-11-21) that
`khulnaplex_adapter_test.dart` runs against, so the tests need no
connection. Each page was cut down by a script to its menu, its one script
tag and the part the adapter reads. The markup of what is kept is
unchanged.

| File | What | Kept |
|---|---|---|
| `home.html` | the front page | the menu and the script tag, by which the site is told |
| `movies_page_1.html` | `movies.php` | the first three films and the page numbers |
| `movies_page_last.html` | `movies.php?page=63`, the last page | two films and the page numbers |
| `movies_page_past_the_end.html` | `movies.php?page=64` | an empty list, as the site shows it |
| `series_page_1.html` | `series.php` | the first three shows |
| `watch_movie.html` | `watch.php?id=1357&type=movie` | the player with the file it names, the title and the year |
| `watch_series.html` | `watch.php?id=1&type=series` | the same, and the first three episodes of the list |
| `watch_episode_2.html` | `watch.php?id=1&type=series&season=1&episode=2` | the same |
