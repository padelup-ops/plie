# ALLÔ PÈRE NOËL : anime le portrait du Père Noël avec sa voix (Ditto, Apache 2.0), dans un carnet Kaggle avec carte graphique.
#
# Dans un nouveau carnet Kaggle (Session options : Accelerator « GPU T4 x2 », Internet activé), une seule cellule :
#
#   !wget -qO run.py https://raw.githubusercontent.com/padelup-ops/plie/main/noel/ai/kaggle_run.py
#   %run run.py
#
# Les vidéos s'affichent sous la cellule, sont rangées dans /kaggle/working/pere-noel-videos.zip, et partent dans le jeu
# de données privé <compte>/allo-pere-noel-videos (que GitHub récupère ensuite). Variables possibles avant %run :
# PORTRAIT (chemin dans le dépôt), AUDIOS (chemins séparés par des espaces), KUSER (nom du compte Kaggle).
import os, shutil, subprocess, sys, time, urllib.request

REPO = "https://raw.githubusercontent.com/padelup-ops/plie/main/"
PORTRAIT = os.environ.get("PORTRAIT", "noel/ai/portrait-2.png")
AUDIOS = os.environ.get("AUDIOS", "noel/ai/essai-fr.wav").split()
KUSER = os.environ.get("KUSER", "hfreecs")
W = "/kaggle/working"
OUT = W + "/out"
IN = "/kaggle/in"
DITTO = "/kaggle/ditto"
os.makedirs(OUT, exist_ok=True)
os.makedirs(IN, exist_ok=True)
log = open(OUT + "/journal.txt", "a")


def note(s):
    print(s, flush=True)
    log.write(s + "\n")
    log.flush()


def sh(c, check=False):
    r = subprocess.run(c, shell=True, capture_output=True, text=True)
    log.write(f"$ {c}\n{r.stdout[-3000:]}{r.stderr[-3000:]}\n")
    log.flush()
    if check and r.returncode != 0:
        note(f"ÉCHEC : {c}\n{r.stderr[-1500:]}")
        raise SystemExit(1)
    return r


t0 = time.time()
gpu = sh("nvidia-smi --query-gpu=name,memory.total --format=csv,noheader").stdout.strip()
note(f"Carte graphique : {gpu or 'AUCUNE (choisis GPU T4 x2 dans Session options, puis relance)'}")
note(f"Python {sys.version.split()[0]}")
if not gpu:
    raise SystemExit(1)

note("1/4 Installation…")
sh("apt-get install -y -qq libegl1 libgles2 ffmpeg > /dev/null 2>&1 || true")
PY = sys.executable
deps = "librosa tqdm filetype imageio imageio-ffmpeg scikit-image cython colored mediapipe einops onnxruntime huggingface_hub soundfile opencv-python-headless"
sh(f"{PY} -m pip install -q {deps}")
if sh(f'{PY} -c "import mediapipe, librosa, torch; assert torch.cuda.is_available()"').returncode != 0:
    # Le Python de Kaggle est trop récent pour une des briques : un Python 3.11 à part, avec PyTorch pour la carte graphique.
    note("   Python 3.11 à part (une brique ne s'installe pas sur ce Python)…")
    sh(f"{PY} -m pip install -q uv", check=True)
    sh("uv venv -q -p 3.11 /kaggle/py311", check=True)
    PY = "/kaggle/py311/bin/python"
    sh(f"uv pip install -q -p {PY} torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu121", check=True)
    sh(f'uv pip install -q -p {PY} {deps} scipy "numpy<2.1"', check=True)
    sh(f'{PY} -c "import mediapipe, librosa, torch; assert torch.cuda.is_available()"', check=True)

note("2/4 Ditto et ses modèles…")
if not os.path.isdir(DITTO):
    sh(f"git clone -q --depth 1 https://github.com/antgroup/ditto-talkinghead {DITTO}", check=True)
sh(f'''{PY} -c "from huggingface_hub import snapshot_download; snapshot_download('digital-avatar/ditto-talkinghead', local_dir='{DITTO}/checkpoints', allow_patterns=['ditto_pytorch/*', 'ditto_pytorch/**', 'ditto_cfg/*'])"''', check=True)

note("3/4 Animation…")
src = IN + "/" + os.path.basename(PORTRAIT)
urllib.request.urlretrieve(REPO + PORTRAIT, src)
videos = []
for a in AUDIOS:
    dst = IN + "/" + os.path.basename(a)
    urllib.request.urlretrieve(REPO + a, dst)
    out = OUT + "/" + os.path.splitext(os.path.basename(a))[0] + ".mp4"
    t = time.time()
    r = subprocess.run([PY, "inference.py", "--data_root", "./checkpoints/ditto_pytorch",
                        "--cfg_pkl", "./checkpoints/ditto_cfg/v0.4_hubert_cfg_pytorch.pkl",
                        "--audio_path", dst, "--source_path", src, "--output_path", out],
                       cwd=DITTO, capture_output=True, text=True)
    open(OUT + "/log-" + os.path.basename(a) + ".txt", "w").write(r.stdout[-6000:] + r.stderr[-6000:])
    ok = r.returncode == 0 and os.path.exists(out)
    note(f"   {a} : {'OK' if ok else 'ÉCHEC'} en {time.time() - t:.0f} s")
    if ok:
        videos.append(out)
    else:
        note(r.stderr[-1500:])

note("4/4 Envoi…")
shutil.make_archive(W + "/pere-noel-videos", "zip", OUT)
try:
    from IPython.display import Video, display
    for v in videos:
        display(Video(v, embed=True, width=360))
except Exception:
    pass
try:
    sh(f"{sys.executable} -m pip install -q -U kagglehub")
    import kagglehub
    kagglehub.dataset_upload(f"{KUSER}/allo-pere-noel-videos", OUT, version_notes=f"{len(videos)} vidéo(s)")
    note(f"Envoyé dans le jeu de données privé {KUSER}/allo-pere-noel-videos. Dis à Claude que c'est fini.")
except Exception as e:
    note(f"Envoi automatique impossible ({e}). Télécharge /kaggle/working/pere-noel-videos.zip (panneau Output) et envoie-le à Claude.")
note(f"Terminé en {(time.time() - t0) / 60:.1f} min, {len(videos)}/{len(AUDIOS)} vidéo(s).")
