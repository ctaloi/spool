/**
 * Bees Playbook Trainer — shared leaderboard (Cloudflare Worker).
 *
 * Setup: create a Worker with this script and bind a KV namespace
 * named BOARD (Settings -> Bindings -> KV Namespace). Then point the
 * site at it via config.js (see README.md).
 */
const PASSWORD = "gobees";
const MAX_ROWS = 200;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "OPTIONS") return new Response(null, { headers: CORS });

    if (url.pathname === "/board" && request.method === "GET") {
      const rows = JSON.parse((await env.BOARD.get("rows")) || "[]");
      return json(rows);
    }

    if (url.pathname === "/score" && request.method === "POST") {
      let body;
      try { body = await request.json(); } catch { return json({ error: "bad json" }, 400); }
      if (body.pw !== PASSWORD) return json({ error: "nope" }, 403);

      const name = String(body.name || "").slice(0, 14).replace(/[<>&]/g, "");
      const yards = Math.max(0, Math.min(500, Number(body.yards) | 0));
      const mode = String(body.mode || "").slice(0, 24).replace(/[<>&]/g, "");
      if (!name || !yards) return json({ error: "missing fields" }, 400);

      const rows = JSON.parse((await env.BOARD.get("rows")) || "[]");
      rows.push({ name, yards, mode, ts: Date.now() });
      rows.sort((a, b) => b.yards - a.yards);
      await env.BOARD.put("rows", JSON.stringify(rows.slice(0, MAX_ROWS)));
      return json({ ok: true });
    }

    return json({ error: "not found" }, 404);
  },
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json", ...CORS },
  });
}
