# Sample pages of FlixHub

Saved answers of `https://flixhub.net/` (2026-11-21) that
`flixhub_adapter_test.dart` runs against, so the tests need no connection.
The real pages are hundreds of kilobytes; each was cut down to a few cards
by a script. The markup of what is kept is unchanged.

| File | What | Kept |
|---|---|---|
| `home.html` | the front page | its navigation bar (by which the site is told) and two cards |
| `movies_page_1.json` | `/movies?page=1`, asked the way the site's own script asks: JSON with a piece of HTML | the first three films |
| `movies_page_2.json` | the last page of the list (page 68) | two films; `current_page`, `last_page` and `total` rewritten so that it is page 2 of 2 |
| `movies_page_past_the_end.json` | `/movies?page=69`, one past the end | all of it |
| `tv_shows.html` | `/tv-shows`: every show on one page | three shows, one of them twice, as on the real page |
| `series.html` | `/watch/series/reacher`: every episode of a show | three episodes of season 1 and two of season 2 |
