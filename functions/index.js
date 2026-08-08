const {onRequest} = require("firebase-functions/v2/https");
const {defineSecret} = require("firebase-functions/params");
const {initializeApp} = require("firebase-admin/app");
const {getAuth} = require("firebase-admin/auth");

const tmdbApiKey = defineSecret("TMDB_API_KEY");
const tvdbApiKey = defineSecret("TVDB_API_KEY");

initializeApp();

const upstreams = {
  tmdb: "https://api.themoviedb.org/3",
  tvdb: "https://api4.thetvdb.com/v4",
};

// TheTVDB tokens last about a month. A warm instance reuses one instead of
// logging in on every request; a cold one logs in again.
let tvdbToken = null;
let tvdbTokenExpiry = 0;

async function tvdbBearer() {
  if (tvdbToken && Date.now() < tvdbTokenExpiry) return tvdbToken;
  const r = await fetch(`${upstreams.tvdb}/login`, {
    method: "POST",
    headers: {"content-type": "application/json"},
    body: JSON.stringify({apikey: tvdbApiKey.value()}),
  });
  if (!r.ok) throw new Error(`TheTVDB login failed: ${r.status}`);
  const body = await r.json();
  tvdbToken = body.data && body.data.token;
  if (!tvdbToken) throw new Error("TheTVDB login returned no token");
  tvdbTokenExpiry = Date.now() + 24 * 60 * 60 * 1000;
  return tvdbToken;
}

async function callerUid(req) {
  const header = req.get("authorization") || "";
  if (!header.startsWith("Bearer ")) return null;
  try {
    const decoded = await getAuth().verifyIdToken(header.slice(7));
    return decoded.uid;
  } catch (_) {
    return null;
  }
}

/// Read-only proxy for the metadata providers: it holds the API keys so the
/// APK never carries them, and answers only signed-in callers.
exports.metadata = onRequest(
    {
      region: "europe-west1",
      secrets: [tmdbApiKey, tvdbApiKey],
      maxInstances: 10,
      timeoutSeconds: 30,
    },
    async (req, res) => {
      if (req.method !== "GET") {
        res.status(405).json({error: "Only GET is proxied"});
        return;
      }
      if (!(await callerUid(req))) {
        res.status(401).json({error: "Sign-in required"});
        return;
      }

      const segments = req.path.split("/").filter((s) => s.length > 0);
      const provider = segments.shift();
      const base = upstreams[provider];
      if (!base || segments.some((s) => s === "..")) {
        res.status(404).json({error: "Unknown provider"});
        return;
      }

      const url = new URL(`${base}/${segments.join("/")}`);
      for (const [key, value] of Object.entries(req.query)) {
        url.searchParams.set(key, String(value));
      }

      const headers = {accept: "application/json"};
      if (provider === "tmdb") {
        url.searchParams.set("api_key", tmdbApiKey.value());
      } else {
        headers.authorization = `Bearer ${await tvdbBearer()}`;
      }

      try {
        const upstream = await fetch(url, {headers});
        res
            .status(upstream.status)
            .type(upstream.headers.get("content-type") || "application/json")
            .send(await upstream.text());
      } catch (e) {
        res.status(502).json({error: "Upstream unreachable"});
      }
    },
);
