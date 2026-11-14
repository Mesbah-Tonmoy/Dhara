# Sample TMDB answers

Answers the TMDB client tests run against, served by a stand-in server on
the loopback interface, so the tests need neither a TMDB key nor a
connection.

Written by hand in the format the TMDB reference documents (read on
2026-11-14), because no key was at hand to capture real answers. Titles,
ids and texts are made up. Some entries are broken on purpose: the client
has to skip or clean them.

| File | Endpoint | Broken on purpose |
|---|---|---|
| `search_movie.json` | `GET /3/search/movie` | an image path that climbs out of its folder, one that is a full address, a result without an id, one without a title, one that is not an object; more results than the client keeps |
| `search_tv.json` | `GET /3/search/tv` | a date that is not a date |
| `movie.json` | `GET /3/movie/{id}` | a genre without a name |
| `tv.json` | `GET /3/tv/{id}` | a season without a number |
| `season.json` | `GET /3/tv/{id}/season/{n}` | an episode without a number |
