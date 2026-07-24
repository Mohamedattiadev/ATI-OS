# wal-precompile report

- wallpapers: 363
- avg score: 99.7
- >=80: 363 (100%)
- <70: 0
- elapsed: 54.4s

## Deep-test vs doomone-quality bar

Doomone hand-tuned min-pair RGB distance = 0.18 (blue↔cyan). Every
precompiled palette meets or exceeds every doomone metric:

| check | 363 pass? |
|---|---|
| WCAG AAA bg/fg contrast (>=7:1) | 363/363 |
| WCAG AA all 6 accents vs bg (>=4.5:1) | 363/363 |
| min accent pair distance >= doomone (0.18) | 363/363 |

- avg min accent pair distance: **0.33** (1.8x doomone baseline)
- worst case: 0.217 (still 1.2x doomone)

## Worst 20

| wallpaper | score | bg | fg | accents | notes |
|---|---|---|---|---|---|
| 0330.jpg | 96.0 | `#181211` | `#dddada` | `#e88273` `#e8e073` `#9fe873` `#73e8bc` `#73b9e8` `#8273e8` |  |
| 0187.jpg | 97.7 | `#181111` | `#dddada` | `#e8a573` `#dbe873` `#73e880` `#73dbe8` `#7383e8` `#d873e8` |  |
| 0073.jpg | 97.9 | `#181113` | `#dddadb` | `#e87a73` `#e8cf73` `#8ce873` `#73e8cf` `#73a9e8` `#b273e8` |  |
| 0099.jpg | 97.9 | `#181811` | `#ddddda` | `#e8ce73` `#ade873` `#73e8ae` `#73cae8` `#9173e8` `#e873ca` |  |
| 0304.jpg | 97.9 | `#181115` | `#dddadc` | `#e8b173` `#cbe873` `#73e890` `#73cbe8` `#7373e8` `#e873e8` |  |
| 0316.jpg | 97.9 | `#181711` | `#ddddda` | `#e8c873` `#b2e873` `#73e8a9` `#73cfe8` `#8b73e8` `#e873cf` |  |
| 0002.jpg | 98.0 | `#111518` | `#dadbdd` | `#e8cb73` `#90e873` `#73e8cb` `#73abe8` `#9073e8` `#e873cb` |  |
| 0023.jpg | 98.0 | `#171811` | `#ddddda` | `#e8bd73` `#9ee873` `#73e8bd` `#73c5e8` `#8273e8` `#e873d9` |  |
| 0028.jpg | 98.0 | `#111418` | `#dadbdd` | `#e8d473` `#87e873` `#73e8b6` `#73b3e8` `#9973e8` `#e873c2` |  |
| 0034.jpg | 98.0 | `#111718` | `#dadcdd` | `#e8bc73` `#9fe873` `#73e8bc` `#73b6e8` `#8173e8` `#e873da` |  |
| 0038.jpg | 98.0 | `#161811` | `#dcddda` | `#e89e73` `#bde873` `#73e89e` `#73dce8` `#7382e8` `#d973e8` |  |
| 0048.jpg | 98.0 | `#111817` | `#dadddc` | `#e89873` `#c3e873` `#73e87b` `#73e8e1` `#7388e8` `#d373e8` |  |
| 0079.jpg | 98.0 | `#141118` | `#dbdadd` | `#e87373` `#e8e873` `#73e873` `#73e8e8` `#7399e8` `#ad73e8` |  |
| 0089.jpg | 98.0 | `#171811` | `#ddddda` | `#e8ad73` `#d0e873` `#73e873` `#73e8e8` `#7373e8` `#e873e8` |  |
| 0159.jpg | 98.0 | `#181711` | `#ddddda` | `#e8bf73` `#9ce873` `#73e8a2` `#73c5e8` `#8473e8` `#e873d6` |  |
| 0196.jpg | 98.0 | `#111618` | `#dadcdd` | `#e8ab73` `#b0e873` `#73e8ab` `#73cae8` `#7375e8` `#e673e8` |  |
| 0280.jpg | 98.0 | `#161811` | `#dcddda` | `#e8bf73` `#9ce873` `#73e8bf` `#73b5e8` `#8473e8` `#e873d7` |  |
| 0299.jpg | 98.0 | `#111518` | `#dadcdd` | `#e8ac73` `#afe873` `#73e8ac` `#73c4e8` `#7374e8` `#e773e8` |  |
| 0301.jpg | 98.0 | `#181811` | `#ddddda` | `#e8a573` `#dbe873` `#7be873` `#73e8df` `#737be8` `#df73e8` |  |
| 0264.jpg | 98.1 | `#181811` | `#ddddda` | `#e8b773` `#a1e873` `#73e8ba` `#73b7e8` `#7f73e8` `#e873db` |  |