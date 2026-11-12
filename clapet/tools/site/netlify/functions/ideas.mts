// La boîte à idées de Foldly : les utilisateurs proposent des idées et votent ; le développeur répond
// (prévu / fait / pas pour l'instant), cache ou supprime. Stockage : Netlify Blobs (une clé par idée,
// une clé par vote : pas de compteur à modifier, le total = le nombre de clés).
//
// Clés :  i/<id>  l'idée (JSON)  ·  v/<id>/<auteur>  un vote  ·  r/<id>/<auteur>  un signalement
//         ban/<auteur>  auteur bloqué  ·  q/<auteur>/<jour>/<id>  pour limiter les envois
// <auteur> : empreinte (SHA-256) de l'identifiant Game Center, jamais l'identifiant lui-même.
import { getStore } from "@netlify/blobs"
import type { Config, Context } from "@netlify/functions"

const ADMIN_SHA256 = "3eaa752c5acd51269c3786c96c61038eb892637c1133788e963c44df39fbeca2"
const store = () => getStore({ name: "foldly-ideas", consistency: "strong" })
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" } })

type Idea = {
  id: string; title: string; body: string; alias: string; author: string; folds: number; lang: string
  created: number; status: "open" | "planned" | "done" | "declined"; reply?: string; hidden?: boolean
}

// Filtre de base (Apple demande de filtrer les contenus choquants) : insultes courantes FR / EN, liens.
const BAD = ["fuck", "shit", "bitch", "cunt", "nigg", "fag", "retard", "whore", "slut", "dick", "pussy", "porn",
  "putain", "merde", "connard", "connasse", "salope", "enculé", "encule", "pute", "batard", "bâtard", "nique", "pd ",
  "fdp", "tg ", "ntm", "hitler", "nazi"]
const clean = (s: string) => s.replace(/[\u0000-\u001f]/g, " ").replace(/\s+/g, " ").trim()
const offensive = (s: string) => {
  const t = " " + s.toLowerCase() + " "
  return BAD.some(w => t.includes(w)) || /https?:\/\/|www\.|\.(com|net|org|ru|io)\b/.test(t)
}
const okAuthor = (a: unknown): a is string => typeof a === "string" && /^[a-f0-9]{16,64}$/.test(a)

async function counts(prefix: string) {
  const { blobs } = await store().list({ prefix })
  const m = new Map<string, Set<string>>()
  for (const b of blobs) {
    const [, id, who] = b.key.split("/")
    if (!m.has(id)) m.set(id, new Set())
    m.get(id)!.add(who)
  }
  return m
}

async function allIdeas() {
  const s = store()
  const { blobs } = await s.list({ prefix: "i/" })
  const ideas = await Promise.all(blobs.map(b => s.get(b.key, { type: "json" }) as Promise<Idea | null>))
  return ideas.filter((x): x is Idea => !!x)
}

async function listing(viewer: string | null, admin = false) {
  const [ideas, votes, reports] = await Promise.all([allIdeas(), counts("v/"), counts("r/")])
  return ideas
    .filter(i => admin || !i.hidden)
    .map(i => ({
      id: i.id, title: i.title, body: i.body, alias: i.alias, folds: i.folds, lang: i.lang, created: i.created,
      status: i.status, reply: i.reply ?? null, votes: votes.get(i.id)?.size ?? 0,
      voted: viewer ? votes.get(i.id)?.has(viewer) ?? false : false,
      mine: viewer ? i.author === viewer : false,
      author: i.author.slice(0, 12),
      ...(admin ? { hidden: !!i.hidden, reports: reports.get(i.id)?.size ?? 0 } : {}),
    }))
    .sort((a, b) => b.votes - a.votes || b.created - a.created)
}

export default async (req: Request, context: Context) => {
  const url = new URL(req.url)
  const parts = url.pathname.replace(/^\/api\/ideas\/?/, "").split("/").filter(Boolean)
  const s = store()

  // --- Modération (le développeur) : clé secrète dans l'en-tête x-admin-key.
  if (parts[0] === "admin") {
    // La clé de modération : la variable IDEAS_ADMIN_KEY si elle existe, sinon on compare son empreinte (la clé n'est pas dans le code).
    const given = req.headers.get("x-admin-key") ?? ""
    const env = Netlify.env.get("IDEAS_ADMIN_KEY")
    const digest = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(given))))
      .map(x => x.toString(16).padStart(2, "0")).join("")
    if (!given || (env ? given !== env : digest !== ADMIN_SHA256)) return json({ error: "forbidden" }, 403)
    if (req.method === "GET") return json({ ideas: await listing(null, true) })
    const b = await req.json().catch(() => ({})) as Record<string, any>
    const idea = b.id ? await s.get("i/" + b.id, { type: "json" }) as Idea | null : null
    switch (b.action) {
      case "status":
        if (!idea || !["open", "planned", "done", "declined"].includes(b.status)) return json({ error: "bad" }, 400)
        idea.status = b.status; await s.setJSON("i/" + idea.id, idea); return json({ ok: true })
      case "reply":
        if (!idea) return json({ error: "bad" }, 400)
        idea.reply = clean(String(b.reply ?? "")).slice(0, 400) || undefined; await s.setJSON("i/" + idea.id, idea); return json({ ok: true })
      case "hide": case "unhide":
        if (!idea) return json({ error: "bad" }, 400)
        idea.hidden = b.action === "hide"; await s.setJSON("i/" + idea.id, idea); return json({ ok: true })
      case "delete":
        if (!idea) return json({ error: "bad" }, 400)
        await s.delete("i/" + idea.id); return json({ ok: true })
      case "ban": {
        // L'auteur de cette idée : bloqué, et toutes ses idées cachées.
        if (!idea) return json({ error: "bad" }, 400)
        await s.set("ban/" + idea.author, "1")
        for (const i of await allIdeas()) if (i.author === idea.author) { i.hidden = true; await s.setJSON("i/" + i.id, i) }
        return json({ ok: true })
      }
    }
    return json({ error: "unknown action" }, 400)
  }

  // --- Lecture : GET /api/ideas?me=<auteur>
  if (req.method === "GET" && parts.length === 0) {
    const me = url.searchParams.get("me")
    return json({ ideas: await listing(okAuthor(me) ? me : null) })
  }

  if (req.method !== "POST") return json({ error: "method" }, 405)
  const b = await req.json().catch(() => ({})) as Record<string, any>
  if (!okAuthor(b.author)) return json({ error: "author" }, 400)
  if (await s.get("ban/" + b.author)) return json({ error: "banned" }, 403)

  // --- Nouvelle idée : POST /api/ideas { author, alias, folds, lang, title, body }
  if (parts.length === 0) {
    const title = clean(String(b.title ?? "")).slice(0, 90)
    const body = clean(String(b.body ?? "")).slice(0, 600)
    const alias = clean(String(b.alias ?? "")).slice(0, 30) || "Duo"
    if (title.length < 4) return json({ error: "short" }, 400)
    if (offensive(title) || offensive(body) || offensive(alias)) return json({ error: "filtered" }, 422)
    const day = new Date().toISOString().slice(0, 10)
    const { blobs } = await s.list({ prefix: `q/${b.author}/${day}/` })
    if (blobs.length >= 3) return json({ error: "limit" }, 429)
    const id = Date.now().toString(36) + Math.random().toString(36).slice(2, 7)
    const idea: Idea = { id, title, body, alias, author: b.author, folds: Math.max(0, Math.min(10_000_000, Number(b.folds) | 0)),
      lang: String(b.lang ?? "").slice(0, 8), created: Date.now(), status: "open" }
    await s.setJSON("i/" + id, idea)
    await s.set(`q/${b.author}/${day}/${id}`, "1")
    await s.set(`v/${id}/${b.author}`, "1")   // on vote pour sa propre idée
    return json({ ok: true, id })
  }

  const id = parts[0]
  if (!/^[a-z0-9]{6,20}$/.test(id)) return json({ error: "id" }, 400)
  const idea = await s.get("i/" + id, { type: "json" }) as Idea | null
  if (!idea) return json({ error: "not found" }, 404)

  // --- Vote : POST /api/ideas/<id>/vote { author, on }
  if (parts[1] === "vote") {
    if (b.on === false) await s.delete(`v/${id}/${b.author}`)
    else await s.set(`v/${id}/${b.author}`, "1")
    return json({ ok: true })
  }
  // --- Signalement : POST /api/ideas/<id>/report { author }. Trois signalements : cachée en attendant la modération.
  if (parts[1] === "report") {
    await s.set(`r/${id}/${b.author}`, String(b.reason ?? "").slice(0, 200) || "1")
    const { blobs } = await s.list({ prefix: `r/${id}/` })
    if (blobs.length >= 3 && !idea.hidden) { idea.hidden = true; await s.setJSON("i/" + id, idea) }
    return json({ ok: true })
  }
  // --- Supprimer sa propre idée : POST /api/ideas/<id>/delete { author }
  if (parts[1] === "delete") {
    if (idea.author !== b.author) return json({ error: "forbidden" }, 403)
    await s.delete("i/" + id)
    return json({ ok: true })
  }
  return json({ error: "unknown" }, 400)
}

export const config: Config = {
  path: ["/api/ideas", "/api/ideas/*"],
  rateLimit: { windowLimit: 60, windowSize: 60, aggregateBy: ["ip", "domain"] },
}
