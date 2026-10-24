import { getStore } from "@netlify/blobs"
import type { Config, Context } from "@netlify/functions"

// Compteur des vrais arbres d'Origamo.
// L'app envoie un seul message quand un joueur a fait fleurir les 8 plantes de FERME.
// Rien n'identifie la personne : on enregistre seulement la date. Chaque jardin terminé
// est une entrée à part (pas de compteur modifié en place), le total est leur nombre.

const store = () => getStore({ name: "arbres", consistency: "strong" })

async function total(): Promise<number> {
  const { blobs } = await store().list({ prefix: "jardin/" })
  return blobs.length
}

export default async (req: Request, context: Context) => {
  if (req.method === "GET") {
    return Response.json({ arbres: await total() })
  }
  if (req.method !== "POST") {
    return new Response("Méthode non prise en charge", { status: 405 })
  }
  let body: unknown
  try {
    body = await req.json()
  } catch {
    return new Response("JSON attendu", { status: 400 })
  }
  const event = (body as { event?: unknown })?.event
  if (event !== "jardin-complet") {
    return new Response("Événement inconnu", { status: 400 })
  }
  const day = new Date().toISOString().slice(0, 10)
  await store().setJSON(`jardin/${Date.now()}-${crypto.randomUUID()}`, { jour: day }, { onlyIfNew: true })
  return Response.json({ arbres: await total() })
}

export const config: Config = {
  path: "/api/arbre",
  method: ["GET", "POST"],
  rateLimit: { windowLimit: 10, windowSize: 60, aggregateBy: ["ip", "domain"] },
}
