# Pywal palette audit

Sample: **200** wallpapers from `~/Pictures/Wallpapers/` processed with `wal --backend colorz`.

## Summary

- Monochrome (hue spread < 60°): **32** (16%)
- Low-saturation (<0.25): **24** (12%)
- Dark accents (val_mean < 0.35): **0** (0%)

## Worst monochrome examples (hue spread near 0)

| Wallpaper | hue_spread | sat_mean | val_mean | bg | fg | accents |
|---|---|---|---|---|---|---|
| 0192.jpg | 6.0 | 0.47 | 0.72 | `#0e1c20` | `#c2c6c7` | `#66a7bf` `#89b5c7` `#adbfc7` `#5491af` `#3c86ab` `#2b7baa` |
| 0184.jpg | 7.4 | 0.41 | 0.68 | `#101b27` | `#c3c6c9` | `#336aaa` `#4775aa` `#5a7ba9` `#6f86aa` `#a1adc2` `#8592ab` |
| 0198.jpg | 7.8 | 0.62 | 0.70 | `#101b25` | `#c3c6c8` | `#246dac` `#0a60aa` `#3b76ad` `#5380ab` `#5b8dc1` `#8ba3c6` |
| 0114.jpg | 7.9 | 0.42 | 0.71 | `#1d130c` | `#c6c4c2` | `#aa774c` `#aa865b` `#c7b298` `#c7a477` `#ab8d63` `#b8986a` |
| 0136.jpg | 8.0 | 0.67 | 0.71 | `#171109` | `#c5c3c1` | `#aa6208` `#af7622` `#c79744` `#aa843e` `#a98b4c` `#c6ae79` |
| 0040.jpg | 10.0 | 0.51 | 0.69 | `#111c28` | `#c3c6c9` | `#4077aa` `#5783aa` `#6c93b7` `#82a5c5` `#7f95aa` `#0d46aa` |
| 0041.jpg | 13.8 | 0.29 | 0.70 | `#131312` | `#c4c4c3` | `#aaa39e` `#c6bbb1` `#a99b8e` `#aa926d` `#c49f64` `#aa884a` |
| 0133.jpg | 14.5 | 0.55 | 0.69 | `#0f1a23` | `#c3c5c8` | `#87a4c5` `#6e8eb3` `#597daa` `#4871aa` `#3062aa` `#1839aa` |
| 0075.jpg | 15.4 | 0.66 | 0.71 | `#0f1e23` | `#c3c6c8` | `#0c8bb5` `#0563aa` `#4684b3` `#99abba` `#276fab` `#6594c4` |
| 0144.jpg | 16.1 | 0.64 | 0.67 | `#181b0c` | `#c5c6c2` | `#89aa43` `#7caa2b` `#8aaa56` `#7eaa4b` `#72aa3c` `#5eaa29` |

## Best (widest hue spread)

| Wallpaper | hue_spread | sat_mean | val_mean | bg | fg | accents |
|---|---|---|---|---|---|---|
| 0110.jpg | 352.1 | 0.36 | 0.69 | `#200d0d` | `#c7c2c2` | `#aa7674` `#c77c78` `#aa7062` `#aa867b` `#a9a289` `#b94f59` |
| 0082.jpg | 348.0 | 0.29 | 0.70 | `#151313` | `#c4c4c4` | `#b0a5a5` `#aa5a4c` `#ae7d63` `#b79784` `#a7637b` `#c4bfc0` |
| 0125.jpg | 347.4 | 0.72 | 0.73 | `#20100d` | `#c7c3c2` | `#c7695d` `#2679c7` `#9110a8` `#aa0e7d` `#b30d44` `#c69da1` |
| 0079.jpg | 347.2 | 0.29 | 0.69 | `#1f100d` | `#c7c3c2` | `#b26e5e` `#546eaa` `#7d82ab` `#b5b3c1` `#a48ba4` `#af8384` |
| 0051.jpg | 347.0 | 0.41 | 0.70 | `#171110` | `#c5c3c3` | `#c7928f` `#456baa` `#6f77aa` `#9f82a6` `#b96a7c` `#b85061` |
| 0068.jpg | 345.7 | 0.59 | 0.68 | `#1e100c` | `#c6c3c2` | `#af644f` `#aa4e29` `#aa470c` `#b96712` `#a394a3` `#ab7a7b` |
| 0139.jpg | 342.1 | 0.39 | 0.67 | `#1d0f0c` | `#c6c3c2` | `#ac574b` `#b99891` `#7e9aa5` `#a47b9f` `#a2347a` `#ab6c77` |
| 0200.jpg | 341.6 | 0.41 | 0.69 | `#1d0f0c` | `#c6c3c2` | `#ab5a48` `#c69975` `#4f6eaa` `#7f8fb2` `#a77c9a` `#aa6a72` |
| 0180.jpg | 341.2 | 0.43 | 0.67 | `#20110e` | `#c7c3c2` | `#aa807a` `#aa6e4a` `#ac5e2c` `#a49e4b` `#8380aa` `#b09096` |
| 0177.jpg | 340.9 | 0.36 | 0.70 | `#20100d` | `#c7c3c2` | `#aa7a77` `#aa7062` `#c5a08b` `#c58756` `#a9668e` `#aa8f96` |

## Recommendations

- Keep the hue-spread < 60° fallback in `colors.py._wal_palette`; 16% of wallpapers hit it.
- Add a saturation fallback: if `sat_mean < 0.25`, treat as monochrome and use preset accents.
- Boost `--saturate` in theme-apply if `sat_mean` drops below 0.4 across the sample.