"""Liste toutes les clés L("…") du code (clé = texte, interpolations remplacées par {})."""
import glob
import json
import sys

import i18n_wrap as W

keys = set()
for f in sorted(glob.glob("../Plie/**/*.swift", recursive=True)):
    if f.endswith(W.SKIP_FILES):
        continue
    src = open(f).read()
    i = 0
    while True:
        i = src.find('L("', i)
        if i < 0:
            break
        if i > 0 and (src[i - 1].isalnum() or src[i - 1] == "_"):
            i += 3
            continue
        end, segs = W.scan_literal(src, i + 2)
        keys.add(W.key_of(segs))
        i += 3
json.dump(sorted(keys), open("i18n_keys.json", "w"), ensure_ascii=False, indent=1)
print(len(keys), "clés", file=sys.stderr)
