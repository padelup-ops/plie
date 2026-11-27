// L'entraide de Vicefold (le guide GTA VI) : des questions et des réponses, un fil par mission et un fil général.
// Pas de compte : chaque joueur est l'empreinte (SHA-256) de son identifiant Game Center, jamais l'identifiant
// lui-même, et signe avec son pseudo Game Center. Stockage : Netlify Blobs, une clé par message.
//
// Clés :  p/<sujet>/<id>  le message (JSON)  ·  v/<id>/<auteur>  « utile »  ·  r/<id>/<auteur>  un signalement
//         ban/<auteur>  auteur bloqué par la modération  ·  q/<auteur>/<jour>/<id>  pour limiter les envois
// <sujet> : l'identifiant d'une mission (m1-04…) ou « general ».
// Véhicules rares (Cars.swift dans l'app) : ils passent par les mêmes messages, sans autre route.
//   · sujet « cars » : un message « Nom du véhicule @ 0.6123,0.4571 » est un emplacement ajouté par un joueur ; son vote
//     « utile » veut dire « il est là », une réponse « [not here] » veut dire « pas là » ;
//   · sujet = l'identifiant d'un véhicule de la carte (o-…) : un message « [here] » ou « [not here] » est un vote.
//   Un vote ne compte pas dans la limite d'envois du jour, et chaque joueur n'en garde qu'un par emplacement.
// Apple (règle 1.2) : filtre des contenus choquants, signalement, blocage, modération rapide (caché après 3 signalements).
import { getStore } from "@netlify/blobs"
import type { Config, Context } from "@netlify/functions"

// Même clé de modération que la boîte à idées de Foldly (son empreinte seulement).
const ADMIN_SHA256 = "cc4409730aea4c9313d6435175dbcbaf299879e39b989bd920246741858168ba"
const store = () => getStore({ name: "vicefold-community", consistency: "strong" })
const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store" } })

type Post = {
  id: string; topic: string; parent: string | null; text: string; alias: string; author: string; lang: string
  created: number; hidden?: boolean; spoiler?: boolean
}

// Filtre (FR, EN, ES, DE, IT, PT) : insultes et propos haineux courants, liens, numéros de téléphone.
const BAD = ["fuck", "shit", "bitch", "cunt", "nigg", "fag", "retard", "whore", "slut", "dick", "pussy", "porn", "rape",
  "putain", "connard", "connasse", "salope", "enculé", "encule", "pute ", "batard", "bâtard", "nique ta", "fdp", "ntm",
  "hitler", "nazi", "kys", "kill yourself", "suicide",
  "puta", "cabrón", "cabron", "maricón", "maricon", "gilipollas", "coño", "mierda",
  "fotze", "hurensohn", "wichser", "schlampe", "missgeburt",
  "cazzo", "stronzo", "vaffanculo", "troia", "frocio", "puttana",
  "porra", "caralho", "viado", "buceta", "arrombado", "filho da puta"]
const clean = (s: string) => s.replace(/[\u0000-\u0009\u000b-\u001f]/g, " ").replace(/[ \t]+/g, " ").replace(/\n{3,}/g, "\n\n").trim()
const offensive = (s: string) => {
  const t = " " + s.toLowerCase() + " "
  return BAD.some(w => t.includes(w)) || /https?:\/\/|www\.|\.(com|net|org|ru|io|gg|xyz)\b|discord\.gg|\+?\d[\d .-]{8,}\d/.test(t)
}
const okAuthor = (a: unknown): a is string => typeof a === "string" && /^[a-f0-9]{32,64}$/.test(a)
const okTopic = (t: unknown): t is string => typeof t === "string" && /^(general|[a-z][a-z0-9-]{1,23})$/.test(t)

async function sets(prefix: string) {
  const { blobs } = await store().list({ prefix })
  const m = new Map<string, Set<string>>()
  for (const b of blobs) {
    const [, id, who] = b.key.split("/")
    if (!m.has(id)) m.set(id, new Set())
    m.get(id)!.add(who)
  }
  return m
}

async function posts(prefix: string) {
  const s = store()
  const { blobs } = await s.list({ prefix })
  const all = await Promise.all(blobs.map(b => s.get(b.key, { type: "json" }) as Promise<Post | null>))
  return all.filter((x): x is Post => !!x)
}

function shape(p: Post, votes: Map<string, Set<string>>, viewer: string | null, admin = false, reports?: Map<string, Set<string>>) {
  return {
    id: p.id, topic: p.topic, parent: p.parent, text: p.text, alias: p.alias, lang: p.lang, created: p.created,
    spoiler: !!p.spoiler, votes: votes.get(p.id)?.size ?? 0, voted: viewer ? votes.get(p.id)?.has(viewer) ?? false : false,
    mine: viewer ? p.author === viewer : false, author: p.author.slice(0, 12),
    ...(admin ? { hidden: !!p.hidden, reports: reports?.get(p.id)?.size ?? 0, authorFull: p.author } : {}),
  }
}

async function isAdmin(req: Request) {
  const given = req.headers.get("x-admin-key") ?? ""
  if (!given) return false
  const env = Netlify.env.get("VICEFOLD_ADMIN_KEY") ?? Netlify.env.get("IDEAS_ADMIN_KEY")
  if (env) return given === env
  const digest = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(given))))
    .map(x => x.toString(16).padStart(2, "0")).join("")
  return digest === ADMIN_SHA256
}

export default async (req: Request, _context: Context) => {
  const url = new URL(req.url)
  const parts = url.pathname.replace(/^\/api\/vicefold\/?/, "").split("/").filter(Boolean)
  const s = store()

  // --- Modération : GET /api/vicefold/admin (tout, avec les signalements) ; POST { action, topic, id }
  if (parts[0] === "admin") {
    if (!(await isAdmin(req))) return json({ error: "forbidden" }, 403)
    if (req.method === "GET") {
      const [all, votes, reports] = await Promise.all([posts("p/"), sets("v/"), sets("r/")])
      return json({ posts: all.map(p => shape(p, votes, null, true, reports)).sort((a, b) => b.reports - a.reports || b.created - a.created) })
    }
    const b = await req.json().catch(() => ({})) as Record<string, any>
    if (!okTopic(b.topic) || typeof b.id !== "string") return json({ error: "bad" }, 400)
    const key = `p/${b.topic}/${b.id}`
    const p = await s.get(key, { type: "json" }) as Post | null
    if (!p) return json({ error: "not found" }, 404)
    switch (b.action) {
      case "hide": case "unhide": p.hidden = b.action === "hide"; await s.setJSON(key, p); return json({ ok: true })
      case "delete": await s.delete(key); return json({ ok: true })
      case "ban": {
        await s.set("ban/" + p.author, "1")
        for (const x of await posts("p/")) if (x.author === p.author && !x.hidden) { x.hidden = true; await s.setJSON(`p/${x.topic}/${x.id}`, x) }
        return json({ ok: true })
      }
    }
    return json({ error: "unknown action" }, 400)
  }

  // --- Combien de questions par sujet : GET /api/vicefold/counts
  if (req.method === "GET" && parts[0] === "counts") {
    const all = await posts("p/")
    const c: Record<string, number> = {}
    for (const p of all) if (!p.hidden && !p.parent) c[p.topic] = (c[p.topic] ?? 0) + 1
    return json({ counts: c })
  }

  // --- Un fil : GET /api/vicefold/t/<sujet>?me=<auteur>
  if (req.method === "GET" && parts[0] === "t" && okTopic(parts[1])) {
    const me = url.searchParams.get("me")
    const viewer = okAuthor(me) ? me : null
    const [all, votes] = await Promise.all([posts(`p/${parts[1]}/`), sets("v/")])
    const visible = all.filter(p => !p.hidden)
    const ids = new Set(visible.map(p => p.id))
    const shaped = visible.filter(p => !p.parent || ids.has(p.parent)).map(p => shape(p, votes, viewer))
    return json({ posts: shaped })
  }

  if (req.method !== "POST") return json({ error: "method" }, 405)
  const b = await req.json().catch(() => ({})) as Record<string, any>
  if (!okAuthor(b.author)) return json({ error: "author" }, 400)
  if (await s.get("ban/" + b.author)) return json({ error: "banned" }, 403)

  // --- Nouveau message : POST /api/vicefold/t/<sujet> { author, alias, lang, text, parent?, spoiler? }
  if (parts[0] === "t" && okTopic(parts[1]) && parts.length === 2) {
    const topic = parts[1]
    const text = clean(String(b.text ?? "")).slice(0, 600)
    const alias = clean(String(b.alias ?? "")).replace(/\n/g, " ").slice(0, 30) || "Player"
    if (text.length < 4) return json({ error: "short" }, 400)
    if (offensive(text) || offensive(alias)) return json({ error: "filtered" }, 422)
    let parent: string | null = null
    if (b.parent) {
      if (typeof b.parent !== "string" || !(await s.get(`p/${topic}/${b.parent}`))) return json({ error: "parent" }, 400)
      parent = b.parent
    }
    // Véhicules rares : un vote (« [here] », « [not here] ») ou, dans « cars », un emplacement « Nom @ x,y ».
    const vote = text === "[here]" || text === "[not here]"
    if (topic === "cars" && !(parent ? text === "[not here]" : /^.{2,60} @ [01]\.\d{1,5},[01]\.\d{1,5}$/.test(text))) return json({ error: "format" }, 400)
    const day = new Date().toISOString().slice(0, 10)
    if (vote) {
      // Un seul vote par joueur et par emplacement : le précédent s'efface.
      for (const x of await posts(`p/${topic}/`)) {
        if (x.author === b.author && x.parent === parent && (x.text === "[here]" || x.text === "[not here]")) await s.delete(`p/${topic}/${x.id}`)
      }
    } else {
      const { blobs } = await s.list({ prefix: `q/${b.author}/${day}/` })
      if (blobs.length >= 20) return json({ error: "limit" }, 429)
    }
    const id = Date.now().toString(36) + Math.random().toString(36).slice(2, 7)
    const p: Post = { id, topic, parent, text, alias, author: b.author, lang: String(b.lang ?? "").slice(0, 8), created: Date.now(), spoiler: !!b.spoiler }
    await s.setJSON(`p/${topic}/${id}`, p)
    if (!vote) await s.set(`q/${b.author}/${day}/${id}`, "1")
    return json({ ok: true, id })
  }

  // --- Sur un message : POST /api/vicefold/p/<sujet>/<id>/(vote|report|delete) { author, … }
  if (parts[0] === "p" && okTopic(parts[1]) && /^[a-z0-9]{6,20}$/.test(parts[2] ?? "")) {
    const key = `p/${parts[1]}/${parts[2]}`
    const p = await s.get(key, { type: "json" }) as Post | null
    if (!p) return json({ error: "not found" }, 404)
    switch (parts[3]) {
      case "vote":
        if (b.on === false) await s.delete(`v/${p.id}/${b.author}`)
        else await s.set(`v/${p.id}/${b.author}`, "1")
        return json({ ok: true })
      case "report": {
        await s.set(`r/${p.id}/${b.author}`, String(b.reason ?? "").slice(0, 200) || "1")
        const { blobs } = await s.list({ prefix: `r/${p.id}/` })
        if (blobs.length >= 3 && !p.hidden) { p.hidden = true; await s.setJSON(key, p) }
        return json({ ok: true })
      }
      case "delete":
        if (p.author !== b.author) return json({ error: "forbidden" }, 403)
        await s.delete(key)
        return json({ ok: true })
    }
  }
  return json({ error: "unknown" }, 400)
}

export const config: Config = {
  path: ["/api/vicefold", "/api/vicefold/*"],
  rateLimit: { windowLimit: 90, windowSize: 60, aggregateBy: ["ip", "domain"] },
}
