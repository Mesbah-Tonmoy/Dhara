# Bundled fonts

Both fonts ship inside the app; nothing is fetched at runtime. They are
variable fonts (one file covers every weight) under the SIL Open Font License
1.1; each folder carries its `OFL.txt`.

| Family (as used in code) | File | Source | SHA-256 |
|---|---|---|---|
| `Inter` | `Inter/Inter-Variable.ttf` | [google/fonts `ofl/inter/Inter[opsz,wght].ttf`](https://github.com/google/fonts/tree/main/ofl/inter) | `29160a80ff49ddcab2c97711247e08b1fab27a484a329ce8b813d820dc559031` |
| `Plus Jakarta Sans` | `PlusJakartaSans/PlusJakartaSans-Variable.ttf` | [google/fonts `ofl/plusjakartasans/PlusJakartaSans[wght].ttf`](https://github.com/google/fonts/tree/main/ofl/plusjakartasans) | `89b3fb38aa0d275d7a731d0d817a4f1622b316b4d7fbdedcf02ee9099ff68bc8` |

Downloaded 2026-11-12. The files were renamed only because `[` and `,` are
awkward in asset paths; their contents are unchanged.

Neither font has Bengali glyphs. Bengali text (for example in file names)
falls back to a system font automatically.
