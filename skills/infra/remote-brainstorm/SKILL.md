---
name: mattstack:remote-brainstorm
description: "Expose the superpowers visual brainstorming companion publicly at https://brainstorm.m4tthew.dev so Matt can join a visual brainstorm away from his machine. Use when Matt asks to tunnel the brainstorm companion, run a visual brainstorm remotely, or says things like 'push it through my local apps tunnel' or 'i am not at my machine' during a visual brainstorm."
---

# remote-brainstorm

Companion to superpowers:brainstorming's visual companion. It starts (or
restarts) the companion server and exposes it at
`https://brainstorm.m4tthew.dev` through the portless alias table and the
shared m4tthew.dev wildcard tunnel (mattstack:local-app documents that
pipeline). No per-session tunnel, no DNS route, and no sudo are needed for
the public URL.

Everything about *content* (writing screen fragments, reading click events,
one question per screen) stays with the visual companion guide in the
brainstorming skill. This skill only owns the plumbing that makes the
session reachable remotely.

## Start and tunnel

1. **Reuse a live session if one exists.** For the current repo, a session
   is alive when `state/server-info` exists and `state/server-stopped` does
   not:

   ```bash
   for d in <repo>/.superpowers/brainstorm/*/state; do
     [ -f "$d/server-info" ] && [ ! -f "$d/server-stopped" ] && cat "$d/server-info"
   done
   ```

2. **Otherwise start one.** The start script lives in the brainstorming
   skill's own directory (its base dir is shown when that skill loads;
   the plugin cache version segment changes across releases, so glob for it
   rather than hardcoding):

   ```bash
   <brainstorming-skill-dir>/scripts/start-server.sh --project-dir <repo>
   ```

   Skip `--open` when Matt is remote; there is no local browser to open.
   Capture `port`, `url` (which embeds `?key=...`), `screen_dir`, and
   `state_dir` from the JSON it prints.

3. **Register the alias** (the subdomain is always `brainstorm`):

   ```bash
   portless alias brainstorm <port>
   ```

   If the alias already exists from an earlier session it simply repoints;
   no removal step first.

4. **Verify the public URL.** The first request after aliasing can 404 for
   a few seconds while the local-apps gateway picks up the new alias; retry
   before diagnosing:

   ```bash
   curl -s -o /dev/null -w "%{http_code}" "https://brainstorm.m4tthew.dev/?key=<key>"
   ```

   To isolate a persistent failure, probe the gateway directly:
   `curl -H "Host: brainstorm.m4tthew.dev" "http://localhost:7950/?key=<key>"`.
   If the gateway serves the page but the public URL still 404s, check the
   tunnel service and the publish toggle per mattstack:local-app.

5. **Send Matt the complete URL** including the key:
   `https://brainstorm.m4tthew.dev/?key=<key>`. Never strip the query
   string; the server rejects keyless requests (after the first load a
   cookie carries the key, so reloads work).

Do NOT run the sudo portless proxy restart for this. That restart only
serves the `.localhost` domain, which a remote session never touches; the
public path (Cloudflare tunnel to gateway :7950 to alias table) picks up new
aliases on its own.

## During the session

- The server idle-times-out after 4 hours. If Matt reports a 502 or a
  "paused" overlay, restart with the SAME `--project-dir`: the server
  reuses the port, so the alias stays valid and his open tab reconnects by
  itself.
- A restart mints a NEW session directory. Copy the newest screen HTML into
  the new `content/` dir so his tab shows the current question, and read
  the new `state/server-info`: if the key changed, send the updated URL.

## Cleanup

When the brainstorm ends:

```bash
<brainstorming-skill-dir>/scripts/stop-server.sh <session-dir>
portless alias --remove brainstorm
```

Removing the alias takes brainstorm.m4tthew.dev offline. Mockups persist in
`<repo>/.superpowers/brainstorm/` (keep `.superpowers/` gitignored in the
project repo).

Privacy: the session key gates every request, and the `brainstorm` alias
defaults to published in the local-apps gateway. For anything sensitive,
Matt can unpublish or set a password at `apps.localhost`.
