#!/bin/bash
# Allô Père Noël — publie ce qui est déjà fabriqué (dossier out/) dans la branche des résultats, en l'ajoutant à ce
# que les passages précédents y ont mis. Appelé toutes les quelques minutes pendant la fabrication, et une dernière
# fois à la fin : une machine arrêtée en route ne perd que la phrase en cours.
BR="${BRANCH:-ci-noel-voice}"
TAG="${GITHUB_RUN_ID:-0}-${SHARD:-0}"
URL="https://x-access-token:${GH_PUSH_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
[ -d out ] || exit 0
D="${RUNNER_TEMP:-/tmp}/pub-$$"
trap 'rm -rf "$D"' EXIT
for k in 1 2 3 4 5; do
  rm -rf "$D"
  if ! git clone -q --depth 1 -b "$BR" "$URL" "$D" 2>/dev/null; then
    mkdir -p "$D" && git -C "$D" init -q -b "$BR"
  fi
  mkdir -p "$D/voice" "$D/weak" "$D/reports/$TAG"
  # Les tirages en cours (*.try*, *.wav) restent sur la machine.
  [ -d out/voice ] && rsync -a --exclude '*.try*' --exclude '*.wav' out/voice/ "$D/voice/"
  [ -d out/weak ] && rsync -a --exclude '*.try*' --exclude '*.wav' out/weak/ "$D/weak/"
  cp out/report-*.jsonl out/log-*.txt "$D/reports/$TAG/" 2>/dev/null
  git -C "$D" config user.name "github-actions"
  git -C "$D" config user.email "github-actions@users.noreply.github.com"
  git -C "$D" add -A
  if git -C "$D" diff --cached --quiet; then echo "rien de nouveau à publier"; exit 0; fi
  git -C "$D" commit -qm "Voix du Père Noël : $(find "$D/voice" -name '*.m4a' | wc -l) phrases"
  if git -C "$D" push -q "$URL" "HEAD:$BR"; then
    echo "publié : $(find out/voice -name '*.m4a' ! -name '*.try*' | wc -l) phrases de cette machine"
    exit 0
  fi
  # L'autre machine a publié entre-temps : on reprend sur sa version.
  sleep $((RANDOM % 20 + 5))
done
echo "publication impossible pour l'instant"
exit 1
