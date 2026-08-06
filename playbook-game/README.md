# 🐝 Bees Playbook Trainer

An interactive, touch-first web game that teaches the B'Ville Bees 9U
Power I Right offense. Built for iPhone / iPad Safari — no app install
needed. Kids enter the team password (`gobees`), pick their name, and
earn yards by proving they know the plays.

## Game modes

| Mode | What it teaches |
|------|-----------------|
| 🎬 **Film Room** | Watch every play animate on the field with a kid-friendly coaching cue, or flip to the real coach's card from the playbook PDF. |
| ❓ **Name That Play** | A play runs with no title — pick the right name from 4. Fast answers earn bonus yards. |
| 🏃 **Run Your Route** | Pick your position (Q, 2, 3, or 4). Coach calls a play out loud and three routes light up — tap the one that's YOUR job. Then the real play runs so the assignment sinks in. |
| 🏆 **Leaderboard** | Every drive's total yards is saved. Best score per player per mode. Cross 100 yards in a drive for a TOUCHDOWN celebration. |

Everything is one static folder — `index.html` plus the `cards/` images.
No build step, no dependencies.

## Deploy — GitHub Pages (easiest)

1. Push this `playbook-game/` folder to a repo (it can be its own repo,
   or use this one).
2. In the repo: **Settings → Pages → Source: Deploy from a branch**,
   pick the branch and the folder (use `/ (root)` if the folder is the
   repo root, or move the contents of `playbook-game/` to the root).
3. Share the URL (`https://<user>.github.io/<repo>/`) with the team.

## Deploy — Cloudflare Pages

1. [dash.cloudflare.com](https://dash.cloudflare.com) → **Workers & Pages
   → Create → Pages → Upload assets** (or connect the Git repo).
2. Upload the contents of `playbook-game/`.
3. Done — you get a `*.pages.dev` URL to share.

## The password

The gate password is `gobees` (checked in the browser, stored on the
device after the first entry). This is a friendly gate to keep the link
team-only — it is not real security, which is fine for a playbook that
also lives in every family's email inbox.

## Leaderboard: per-device vs. shared

Out of the box the leaderboard is stored **on each device**
(localStorage) — zero setup, works offline, perfect for one shared
family iPad.

Want one **live leaderboard for the whole team**? Deploy the included
Cloudflare Worker (free tier is plenty):

1. `worker.js` in this folder is the whole backend. In the Cloudflare
   dashboard: **Workers & Pages → Create → Worker**, paste `worker.js`.
2. Add a KV namespace binding named `BOARD`
   (Worker → Settings → Bindings → KV Namespace).
3. Create `config.js` next to `index.html` (copy
   `config.example.js`) and set your worker URL:

   ```js
   window.BEES_API = "https://bees-board.<your-subdomain>.workers.dev";
   ```

4. Redeploy the site. Scores now post to the worker and every device
   sees the same board.

## Updating plays

Plays live in the `PLAYS` array at the top of the `<script>` block in
`index.html` — positions and routes are simple coordinate lists on a
0–100 grid (line of scrimmage at y=42). Add a play object + a card
image in `cards/` and it appears in every game mode automatically.
