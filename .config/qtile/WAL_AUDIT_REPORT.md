# Pywal palette audit

Sample: **50** wallpapers from `~/Pictures/Wallpapers/` processed with `wal --backend colorz`.

## Summary

- Monochrome (hue spread < 60°): **7** (14%)
- Low-saturation (<0.25): **6** (12%)
- Dark accents (val_mean < 0.35): **0** (0%)

## Worst monochrome examples (hue spread near 0)

| Wallpaper | hue_spread | sat_mean | val_mean | bg | fg | accents |
|---|---|---|---|---|---|---|
| 0040.jpg | 10.0 | 0.51 | 0.69 | `#111c28` | `#c3c6c9` | `#4077aa` `#5783aa` `#6c93b7` `#82a5c5` `#7f95aa` `#0d46aa` |
| 0041.jpg | 13.8 | 0.29 | 0.70 | `#131312` | `#c4c4c3` | `#aaa39e` `#c6bbb1` `#a99b8e` `#aa926d` `#c49f64` `#aa884a` |
| 0015.jpg | 22.6 | 0.80 | 0.67 | `#102427` | `#c3c8c9` | `#309fab` `#0e97ad` `#619daa` `#0280aa` `#0368aa` `#256baa` |
| 0013.jpg | 33.1 | 0.64 | 0.70 | `#170d0a` | `#c5c2c1` | `#aa2e11` `#ad6a40` `#ab845f` `#ac5e0b` `#c49948` `#b6a77c` |
| 0008.jpg | 43.8 | 0.52 | 0.68 | `#131212` | `#c4c3c3` | `#a49e9d` `#ab824e` `#aa7125` `#a99169` `#c6a55c` `#a8961a` |
| 0037.jpg | 50.1 | 0.66 | 0.68 | `#171512` | `#c5c4c3` | `#c6b69a` `#aa9a07` `#a79e41` `#a2a471` `#8caa07` `#62aa11` |
| 0027.jpg | 58.9 | 0.50 | 0.66 | `#1c150c` | `#c6c4c2` | `#ab7b46` `#9fa746` `#a1ac85` `#96a967` `#85a932` `#7fa956` |
| 0011.jpg | 63.4 | 0.60 | 0.71 | `#180d0a` | `#c5c2c1` | `#b02f0a` `#b9541a` `#ba8c6c` `#bc7037` `#b5b5b4` `#8aa83d` |
| 0004.jpg | 78.4 | 0.72 | 0.66 | `#18110a` | `#c5c3c1` | `#ab590b` `#a39379` `#a9a62d` `#7dab14` `#48aa11` `#58a943` |
| 0042.jpg | 99.6 | 0.41 | 0.66 | `#0c1b1d` | `#c2c6c6` | `#539da8` `#3292a9` `#497daa` `#6984aa` `#878ca9` `#a798ab` |

## Best (widest hue spread)

| Wallpaper | hue_spread | sat_mean | val_mean | bg | fg | accents |
|---|---|---|---|---|---|---|
| 0039.jpg | 335.3 | 0.28 | 0.69 | `#1f100d` | `#c7c3c2` | `#b1685d` `#5a71aa` `#7680aa` `#9391ac` `#baabbc` `#b09099` |
| 0036.jpg | 325.4 | 0.35 | 0.66 | `#1e0e0c` | `#c6c2c2` | `#aa625c` `#a0a356` `#a1a596` `#94a976` `#7caa52` `#a7778f` |
| 0016.jpg | 324.0 | 0.14 | 0.67 | `#21130e` | `#c7c4c2` | `#aa8f7f` `#aca38c` `#a8a7a4` `#998faa` `#a39ca9` `#aa9499` |
| 0043.jpg | 275.8 | 0.66 | 0.73 | `#1c0f0c` | `#c6c3c2` | `#c15134` `#aeb50e` `#32b814` `#87a4b3` `#3f48b9` `#a958bd` |
| 0026.jpg | 273.4 | 0.41 | 0.70 | `#1f0f0d` | `#c7c3c2` | `#ad6563` `#95afc6` `#7094bf` `#446eaa` `#5b79ab` `#9276a6` |
| 0001.jpg | 245.7 | 0.25 | 0.69 | `#151210` | `#c4c3c3` | `#b29c8d` `#af906a` `#aa8e49` `#8b97b0` `#b8b6bf` `#a4a0a8` |
| 0050.jpg | 245.3 | 0.44 | 0.68 | `#200f0d` | `#c7c3c2` | `#b36b64` `#6ea937` `#6ea0a9` `#3d76a8` `#a1afbf` `#766ba9` |
| 0031.jpg | 235.5 | 0.52 | 0.66 | `#111d0c` | `#c3c6c2` | `#6da24f` `#199d9d` `#517aa9` `#2057aa` `#8489a9` `#b790a1` |
| 0012.jpg | 215.0 | 0.30 | 0.70 | `#131212` | `#c4c3c3` | `#a89999` `#af7b6d` `#b59c5f` `#c2bcaa` `#557eac` `#8a99ae` |
| 0038.jpg | 214.4 | 0.45 | 0.68 | `#21130e` | `#c7c4c2` | `#aa8a7e` `#ab5421` `#aa7352` `#369baa` `#6f96ab` `#a9abb6` |

## Recommendations

- Keep the hue-spread < 60° fallback in `colors.py._wal_palette`; 14% of wallpapers hit it.
- Add a saturation fallback: if `sat_mean < 0.25`, treat as monochrome and use preset accents.
- Boost `--saturate` in theme-apply if `sat_mean` drops below 0.4 across the sample.