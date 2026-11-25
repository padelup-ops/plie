"""Two daily Sales summaries (23 and 24 Nov 2026). Statuses only on stdout."""
import base64
import gzip
import io
import json
import os
import re
import sys
import time
import traceback
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from collections import defaultdict
from datetime import date, timedelta
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

import jwt
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding, rsa
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

API = "https://api.appstoreconnect.apple.com"
MARKER = "PROCEEDS-PLAINTEXT-MARKER-9f3a"
PUB_PATH = Path(__file__).resolve().parent / "asc_nightly_pub.pem"
OUT_PATH = Path("earnings.sealed")
DAYS = (date(2026, 11, 23), date(2026, 11, 24))
RETRY_DAY = date(2026, 11, 24)
SECRETS = []
Q4 = Decimal("0.0001")
Q8 = Decimal("0.00000001")
APP_TYPES = {"1", "1-B", "F1-B", "1E", "1EP", "1EU", "1F", "1T", "F1"}
UPDATE_TYPES = {"7", "7F", "7T", "F7"}
REDOWN_TYPES = {"3", "3F"}
IAP_TYPES = {"FI1", "IA1", "IA1-M"}
SUB_TYPES = {"IA9", "IA9-M", "IAY", "IAY-M"}
LABELS = {
    "com.padelup.clapet": "Foldly",
    "com.padelup.foldboard": "Foldboard",
    "com.padelup.plie": "Origamo",
    "com.padelup.retrofold": "RetroFold",
    "com.padelup.waffle": "Waffle Fold",
    "com.padelup.foldwidgets": "Fold Widgets",
    "com.padelup.foldfx": "FoldFX",
    "com.padelup.unlocked": "Unlocked",
    "com.padelup.padelup-new": "PADELUP",
}


def note_secret(value):
    if value and value not in SECRETS:
        SECRETS.append(value if isinstance(value, str) else str(value))


def redact(msg):
    text = str(msg)
    for secret in SECRETS:
        if secret and secret in text:
            text = text.replace(secret, "[redacted]")
    text = re.sub(r"(vendorNumber(?:=|%3D))[^&\s\"']+", r"\1[redacted]", text, flags=re.I)
    text = re.sub(r"\b\d{6,}\b", "[n]", text)
    return text


def log(msg):
    safe = redact(msg)
    for secret in SECRETS:
        if secret and len(secret) >= 6 and secret in safe:
            print("refusing to log a sensitive value", flush=True)
            raise SystemExit(3)
    print(safe, flush=True)


def D(value):
    text = str(value or "").strip().replace(",", "")
    if text in ("", "-", "−"):
        return Decimal("0")
    try:
        return Decimal(text)
    except Exception:
        return Decimal("0")


def money(value):
    return format(Decimal(value).quantize(Q4, rounding=ROUND_HALF_UP), "f")


def category(ptype):
    if ptype in APP_TYPES:
        return "app"
    if ptype in UPDATE_TYPES:
        return "update"
    if ptype in REDOWN_TYPES:
        return "redownload"
    if ptype in SUB_TYPES:
        return "subscription"
    if ptype in IAP_TYPES or ptype.startswith("IA") or ptype.startswith("FI"):
        return "iap"
    return "other"


def classify(status, body):
    if status == 200:
        return "ok"
    if status == 404:
        return "empty"
    if status in (401, 403, 429, 0):
        return {401: "unauthorized", 403: "forbidden", 429: "rate", 0: "network"}[status]
    try:
        err = json.loads(body.decode("utf-8", "replace"))["errors"][0]
        detail = ((err.get("detail") or "") + " " + (err.get("title") or "")).lower()
        code = err.get("code") or ""
    except Exception:
        return "other"
    if "no sales" in detail or "none were found" in detail:
        return "empty"
    if "no longer available" in detail or "not available" in detail:
        return "gone"
    if "vendor" in detail and "invalid" in detail:
        return "bad_vendor"
    if "version" in detail:
        return "bad_version"
    if status >= 500:
        return "server"
    return "other:" + code[:40]


def decompress(data):
    if data[:2] == b"\x1f\x8b":
        return gzip.decompress(data)
    if data[:2] == b"PK":
        with zipfile.ZipFile(io.BytesIO(data)) as bundle:
            return bundle.read(bundle.namelist()[0])
    return data


def parse_tsv(data):
    text = decompress(data).decode("utf-8-sig", "replace")
    lines = [line for line in text.splitlines() if line.strip()]
    if not lines:
        return []
    header = lines[0].split("\t")
    rows = []
    for line in lines[1:]:
        cols = line.split("\t")
        if len(cols) < len(header):
            cols += [""] * (len(header) - len(cols))
        rows.append(dict(zip(header, cols)))
    return rows


class Client:
    def __init__(self):
        self.token_value = None
        self.token_at = 0

    def token(self):
        if self.token_value and time.time() - self.token_at < 600:
            return self.token_value
        key = os.environ["ASC_PRIVATE_KEY"]
        note_secret(key)
        note_secret(os.environ.get("ASC_KEY_ID", ""))
        note_secret(os.environ.get("ASC_ISSUER_ID", ""))
        now = int(time.time())
        encoded = jwt.encode(
            {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 900, "aud": "appstoreconnect-v1"},
            key, algorithm="ES256", headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
        )
        self.token_value = encoded.decode() if isinstance(encoded, bytes) else encoded
        self.token_at = time.time()
        return self.token_value

    def sales_day(self, vendor, day, version="1_0"):
        query = (
            f"filter[vendorNumber]={urllib.parse.quote(vendor)}"
            f"&filter[reportType]=SALES&filter[reportSubType]=SUMMARY"
            f"&filter[frequency]=DAILY&filter[reportDate]={day.isoformat()}&filter[version]={version}"
        )
        url = f"{API}/v1/salesReports?{query}"
        last = (0, b"")
        for attempt in range(4):
            req = urllib.request.Request(url, headers={"Authorization": "Bearer " + self.token(), "Accept": "application/a-gzip"})
            try:
                with urllib.request.urlopen(req, timeout=90) as res:
                    last = (res.status, res.read())
                    break
            except urllib.error.HTTPError as err:
                last = (err.code, err.read())
                if err.code == 429:
                    time.sleep(min(30, 2 ** attempt))
                    continue
                break
            except Exception:
                last = (0, b"")
                time.sleep(2 ** attempt)
        kind = classify(last[0], last[1])
        if kind == "bad_version" and version == "1_0":
            return self.sales_day(vendor, day, "1_1")
        if kind != "ok":
            return kind, []
        return "ok", parse_tsv(last[1])

    def json_get(self, path):
        req = urllib.request.Request(API + path, headers={"Authorization": "Bearer " + self.token(), "Accept": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=60) as res:
                return json.loads(res.read().decode())
        except Exception:
            return None


def gh_json(method, url, token, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": "Bearer " + token,
        "Accept": "application/vnd.github+json",
        "Content-Type": "application/json",
    })
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            return res.status, json.loads(res.read().decode() or "{}")
    except urllib.error.HTTPError as err:
        err.read()
        return err.code, {}
    except Exception:
        return 0, {}


def publish_runner_pub(token, repo, branch, pub_pem):
    api = "https://api.github.com/repos/" + repo + "/contents/runner.pub"
    status, current = gh_json("GET", api + "?ref=" + urllib.parse.quote(branch, safe="/"), token)
    body = {"message": "One-run public key", "content": base64.b64encode(pub_pem).decode(), "branch": branch}
    if status == 200 and current.get("sha"):
        body["sha"] = current["sha"]
    status, _ = gh_json("PUT", api, token, body)
    log(f"runner pub publish {status}")
    return status in (200, 201)


def receive_sealed_vendor():
    token = os.environ.get("GH_TOKEN") or ""
    repo = os.environ.get("GITHUB_REPOSITORY") or ""
    branch = os.environ.get("GITHUB_REF_NAME") or ""
    if not token or not repo or not branch:
        log("sealed vendor channel unavailable")
        return None
    note_secret(token)
    key = rsa.generate_private_key(public_exponent=65537, key_size=3072)
    pub = key.public_key().public_bytes(serialization.Encoding.PEM, serialization.PublicFormat.SubjectPublicKeyInfo)
    if not publish_runner_pub(token, repo, branch, pub):
        return None
    url = "https://api.github.com/repos/" + repo + "/contents/vendor.sealed?ref=" + urllib.parse.quote(branch, safe="/")
    for attempt in range(45):
        req = urllib.request.Request(url, headers={
            "Authorization": "Bearer " + token,
            "Accept": "application/vnd.github+json",
            "Cache-Control": "no-cache",
        })
        try:
            with urllib.request.urlopen(req, timeout=30) as res:
                payload = json.loads(res.read().decode())
        except urllib.error.HTTPError as err:
            if err.code != 404:
                log(f"sealed poll http {err.code}")
            elif attempt % 3 == 0:
                log("waiting for sealed vendor")
            time.sleep(10)
            continue
        except Exception:
            time.sleep(10)
            continue
        try:
            text = base64.b64decode(payload.get("content") or "").decode().strip()
            vendor = key.decrypt(
                base64.b64decode(text),
                padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA256()), algorithm=hashes.SHA256(), label=None),
            ).decode().strip()
        except Exception:
            log("sealed vendor could not be opened")
            return None
        if not re.fullmatch(r"\d{8,10}", vendor):
            log("sealed vendor shape rejected")
            return None
        note_secret(vendor)
        log("sealed vendor accepted")
        return vendor
    log("sealed vendor timed out")
    return None


def list_apps(client):
    apps = []
    payload = client.json_get("/v1/apps?limit=200")
    if not payload:
        log("apps list failed")
        return apps
    for item in payload.get("data", []):
        attrs = item.get("attributes") or {}
        apps.append({
            "id": str(item.get("id") or ""),
            "name": attrs.get("name") or "",
            "bundleId": attrs.get("bundleId") or "",
            "sku": attrs.get("sku") or "",
        })
    log(f"apps {len(apps)}")
    return apps


def label_for(app):
    bundle = app.get("bundleId") or ""
    if bundle in LABELS:
        return LABELS[bundle]
    return app.get("name") or bundle or "Unknown"


def load_ecb():
    rates = {}
    try:
        with urllib.request.urlopen("https://www.ecb.europa.eu/stats/eurofxref/eurofxref-hist.zip", timeout=90) as res:
            text = decompress(res.read()).decode("utf-8", "replace")
    except Exception:
        log("fx ecb download failed")
        return rates
    header = None
    for line in text.splitlines():
        if line.startswith("Date,") or line.startswith("DATE,"):
            header = [col.strip() for col in line.split(",")]
            continue
        if not header or not line[:1].isdigit():
            continue
        cols = line.split(",")
        row = {}
        for name, value in zip(header[1:], cols[1:]):
            if value and value not in ("N/A", "-"):
                try:
                    row[name.strip()] = Decimal(value)
                except Exception:
                    pass
        if row:
            rates[cols[0].strip()] = row
    log(f"fx ecb days {len(rates)}")
    return rates


def load_spot():
    spot = {}
    try:
        with urllib.request.urlopen("https://open.er-api.com/v6/latest/EUR", timeout=60) as res:
            payload = json.loads(res.read().decode())
        for code, value in (payload.get("rates") or {}).items():
            try:
                spot[code] = Decimal(str(value))
            except Exception:
                pass
        spot["_date"] = str(payload.get("time_last_update_utc") or "latest")[:40]
    except Exception:
        log("fx spot failed")
    log(f"fx spot currencies {len([k for k in spot if not k.startswith('_')])}")
    return spot


def lookup_rate(rates, spot, day, ccy):
    if ccy == "EUR":
        return Decimal("1"), "identity", day.isoformat()
    limit = day.isoformat()
    candidates = [item for item in rates if item <= limit and ccy in rates[item]]
    if candidates:
        chosen = max(candidates)
        return rates[chosen][ccy], "ecb", chosen
    if ccy in spot:
        return spot[ccy], "spot", spot.get("_date", "latest")
    return None, "missing", None


def convert_map(amounts, day, rates, spot):
    eur = Decimal("0")
    usd = Decimal("0")
    native = {}
    missing = {}
    used = {}
    usd_rate, usd_origin, usd_day = lookup_rate(rates, spot, day, "USD")
    if usd_rate is not None:
        used["USD"] = {"rate": format(usd_rate.quantize(Q8), "f"), "origin": usd_origin, "rate_day": usd_day}
    for ccy, amount in amounts.items():
        if amount == 0:
            continue
        native[ccy] = money(amount)
        rate, origin, rate_day = lookup_rate(rates, spot, day, ccy)
        if ccy == "EUR":
            part = amount
        elif rate is None:
            missing[ccy] = money(amount)
            continue
        else:
            part = amount / rate
            used[ccy] = {"rate": format(rate.quantize(Q8), "f"), "origin": origin, "rate_day": rate_day}
        eur += part
        if ccy == "USD":
            usd += amount
        elif usd_rate is not None:
            usd += part * usd_rate
    return eur, usd, native, missing, used


def blank():
    return {
        "downloads": Decimal("0"),
        "paid_app": Decimal("0"),
        "updates": Decimal("0"),
        "redownloads": Decimal("0"),
        "iap": Decimal("0"),
        "customer": defaultdict(Decimal),
        "proceeds": defaultdict(Decimal),
    }


def aggregate(rows, catalog):
    by_sku, by_apple, by_name = {}, {}, {}
    for app in catalog:
        canon = label_for(app)
        if app["sku"]:
            by_sku[app["sku"]] = canon
        if app["id"]:
            by_apple[app["id"]] = canon
        if app["name"]:
            by_name.setdefault(app["name"].casefold(), canon)
    buckets = {label: blank() for label in {label_for(app) for app in catalog} | set(LABELS.values())}

    def key_for(row, level):
        sku = (row.get("SKU") or "").strip()
        parent = (row.get("Parent Identifier") or "").strip()
        apple = (row.get("Apple Identifier") or "").strip()
        title = (row.get("Title") or "").strip()
        if level:
            if apple in by_apple:
                key = by_apple[apple]
            elif sku in by_sku:
                key = by_sku[sku]
            elif title.casefold() in by_name:
                key = by_name[title.casefold()]
            else:
                key = title or sku or "Other"
            if sku:
                by_sku.setdefault(sku, key)
            if apple:
                by_apple.setdefault(apple, key)
            if title:
                by_name.setdefault(title.casefold(), key)
            return key
        if parent in by_sku:
            return by_sku[parent]
        if title.casefold() in by_name:
            return by_name[title.casefold()]
        return parent or title or "Other"

    ordered = sorted(rows, key=lambda row: 0 if category((row.get("Product Type Identifier") or "").strip()) in ("app", "update", "redownload") else 1)
    for row in ordered:
        ptype = (row.get("Product Type Identifier") or "").strip()
        kind = category(ptype)
        units = D(row.get("Units"))
        price = D(row.get("Customer Price"))
        cust = units * price
        proceeds = units * D(row.get("Developer Proceeds"))
        cust_ccy = (row.get("Customer Currency") or "").strip() or "UNK"
        proc_ccy = (row.get("Currency of Proceeds") or "").strip() or "UNK"
        if units == 0 and cust == 0 and proceeds == 0:
            continue
        level = kind in ("app", "update", "redownload")
        key = key_for(row, level)
        bucket = buckets.setdefault(key, blank())
        if kind == "app":
            bucket["downloads"] += units
            if price != 0:
                bucket["paid_app"] += units
        elif kind == "update":
            bucket["updates"] += units
        elif kind == "redownload":
            bucket["redownloads"] += units
        elif kind == "iap" and price != 0:
            bucket["iap"] += units
        if cust != 0 and cust_ccy != "UNK":
            bucket["customer"][cust_ccy] += cust
        if proceeds != 0 and proc_ccy != "UNK":
            bucket["proceeds"][proc_ccy] += proceeds
    return buckets


def pack_day(kind, rows, catalog, day, rates, spot):
    entry = {"status": kind, "apps": {}, "names": sorted({label_for(app) for app in catalog} | set(LABELS.values()))}
    if kind != "ok":
        return entry
    buckets = aggregate(rows, catalog)
    total_c = defaultdict(Decimal)
    total_p = defaultdict(Decimal)
    for name, bucket in buckets.items():
        for ccy, amount in bucket["customer"].items():
            total_c[ccy] += amount
        for ccy, amount in bucket["proceeds"].items():
            total_p[ccy] += amount
        c_eur, c_usd, c_native, c_miss, _ = convert_map(bucket["customer"], day, rates, spot)
        p_eur, p_usd, p_native, p_miss, _ = convert_map(bucket["proceeds"], day, rates, spot)
        entry["apps"][name] = {
            "downloads": money(bucket["downloads"]),
            "paid_app": money(bucket["paid_app"]),
            "updates": money(bucket["updates"]),
            "redownloads": money(bucket["redownloads"]),
            "iap": money(bucket["iap"]),
            "customer": c_native,
            "customer_eur": money(c_eur),
            "customer_usd": money(c_usd),
            "proceeds": p_native,
            "proceeds_eur": money(p_eur),
            "proceeds_usd": money(p_usd),
            "unconverted_customer": c_miss,
            "unconverted_proceeds": p_miss,
        }
    c_eur, c_usd, c_native, c_miss, used = convert_map(total_c, day, rates, spot)
    p_eur, p_usd, p_native, p_miss, p_used = convert_map(total_p, day, rates, spot)
    used.update(p_used)
    sums = blank()
    for bucket in buckets.values():
        for field in ("downloads", "paid_app", "updates", "redownloads", "iap"):
            sums[field] += bucket[field]
    entry.update({
        "downloads": money(sums["downloads"]),
        "paid_app": money(sums["paid_app"]),
        "updates": money(sums["updates"]),
        "redownloads": money(sums["redownloads"]),
        "iap": money(sums["iap"]),
        "customer": c_native,
        "customer_eur": money(c_eur),
        "customer_usd": money(c_usd),
        "proceeds": p_native,
        "proceeds_eur": money(p_eur),
        "proceeds_usd": money(p_usd),
        "unconverted_customer": c_miss,
        "unconverted_proceeds": p_miss,
        "rates": used,
    })
    return entry


def seal(payload):
    payload = dict(payload)
    payload["plaintext_marker"] = MARKER
    public_key = serialization.load_pem_public_key(PUB_PATH.read_bytes())
    aes_key = AESGCM.generate_key(bit_length=256)
    nonce = os.urandom(12)
    ciphertext = AESGCM(aes_key).encrypt(nonce, json.dumps(payload, ensure_ascii=False).encode(), None)
    wrapped = public_key.encrypt(
        aes_key, padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA256()), algorithm=hashes.SHA256(), label=None),
    )
    encoded = json.dumps({
        "v": 1, "alg": "RSA-OAEP-SHA256+AES-256-GCM",
        "ek": base64.b64encode(wrapped).decode(),
        "iv": base64.b64encode(nonce).decode(),
        "ct": base64.b64encode(ciphertext).decode(),
    }, separators=(",", ":"))
    if MARKER in encoded:
        raise SystemExit(4)
    OUT_PATH.write_text(encoded)
    log(f"sealed bytes {OUT_PATH.stat().st_size}")


def unseal(path, private_path):
    blob = json.loads(Path(path).read_text())
    private_key = serialization.load_pem_private_key(Path(private_path).read_bytes(), password=None)
    aes_key = private_key.decrypt(
        base64.b64decode(blob["ek"]),
        padding.OAEP(mgf=padding.MGF1(algorithm=hashes.SHA256()), algorithm=hashes.SHA256(), label=None),
    )
    plain = AESGCM(aes_key).decrypt(base64.b64decode(blob["iv"]), base64.b64decode(blob["ct"]), None)
    return json.loads(plain)


def main():
    if not os.environ.get("ASC_KEY_ID") or not os.environ.get("ASC_ISSUER_ID") or not os.environ.get("ASC_PRIVATE_KEY"):
        seal({"ok": False, "error": "credentials missing"})
        return
    vendor = receive_sealed_vendor()
    if not vendor:
        seal({"ok": False, "error": "vendor_unavailable"})
        log("result vendor missing")
        return
    client = Client()
    apps = list_apps(client)
    rates = load_ecb()
    spot = load_spot()
    fetched = {}
    for day in DAYS:
        kind, rows = client.sales_day(vendor, day)
        log(f"day {day.isoformat()} {kind} rows {len(rows)}")
        fetched[day] = (kind, rows)
    if fetched[RETRY_DAY][0] != "ok":
        log("target day not published, waiting")
        time.sleep(55 * 60)
        kind, rows = client.sales_day(vendor, RETRY_DAY)
        log(f"day {RETRY_DAY.isoformat()} retry {kind} rows {len(rows)}")
        fetched[RETRY_DAY] = (kind, rows)
    days = {}
    for day in DAYS:
        kind, rows = fetched[day]
        days[day.isoformat()] = pack_day(kind, rows, apps, day, rates, spot)
    seal({
        "ok": True,
        "days": days,
        "app_names": sorted({label_for(app) for app in apps}),
        "notes": [
            "Daily SALES SUMMARY. First-time downloads are app product types. Paid units are those with a non-zero customer price. Redownloads are type 3/3F and updates are type 7/7F/7T/F7. Paying IAP units are non-subscription in-app purchases with a non-zero price. Counts are net of refunds.",
            "Customer sales are Units times Customer Price. Developer proceeds are Units times Developer Proceeds. EUR uses the ECB rate on the last published day on or before the sales day (1 EUR = rate). USD is the euro amount times the ECB dollar rate. Currencies missing from the ECB series use one latest spot rate.",
            "An empty day means Apple returned no report. For a day this recent that is the report not being published yet, not a measured zero.",
        ],
    })
    log("result sealed ok")


if __name__ == "__main__":
    if len(sys.argv) >= 4 and sys.argv[1] == "--unseal":
        json.dump(unseal(sys.argv[2], sys.argv[3]), sys.stdout, ensure_ascii=False, indent=2)
        sys.stdout.write("\n")
    else:
        def _hook(exc_type, exc, tb):
            try:
                seal({"ok": False, "error": "exception", "trace": redact("".join(traceback.format_exception(exc_type, exc, tb)))[:4000]})
            except Exception:
                pass
            print("fatal " + exc_type.__name__, flush=True)
            sys.exit(1)
        sys.excepthook = _hook
        main()
