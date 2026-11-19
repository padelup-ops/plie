# RetroFold — licences

Since version 1.0.1, RetroFold as a whole is distributed under the **GNU General Public License v3** (see `LICENSE`),
because the Game Pak's Nintendo DS support uses melonDS DS (GPL v3). Its full source code is this folder.

Parts and their own licences:

| Part | Licence |
|---|---|
| Original RetroFold / RetroCartridge code by Eren Ergeç | MIT (`LICENSE-MIT-ORIGINAL`), kept for those files |
| SameBoy core and boot ROMs (Game Boy / Color), Lior Halphon | Expat / MIT |
| mGBA (Game Boy Advance), Vicki Pfau and contributors | MPL 2.0 — https://github.com/libretro/mgba |
| melonDS DS (Nintendo DS), Jesse Talavera and the melonDS team | GPL v3 — https://github.com/JesseTG/melonds-ds |
| libretro.h | MIT |

The exact versions are pinned in `tools/fetch_sameboy.sh` and `tools/build_cores.sh`.
RetroFold ships no games, BIOS or firmware from Nintendo: players load their own game files.
