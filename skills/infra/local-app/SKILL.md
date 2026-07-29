---
name: mattstack:local-app
description: "Set up a local web app as a persistent macOS service with HTTPS via portless and launchd, automatically public at <name>.m4tthew.dev via the shared wildcard Cloudflare tunnel. Use when the user says 'set up as a local service', 'make this run on localhost', 'add to portless', 'create a launchd service', 'make this a .localhost app', 'expose this publicly', 'add a cloudflare tunnel', or when bootstrapping a new local web project that should run persistently."
---

# local-app

Register a local web app as a persistent macOS service: HTTPS `.localhost` domain via portless, auto-start via launchd, log directory, and health check. Every portless-aliased app is also automatically public at `https://<name>.m4tthew.dev`.

How the public side works: the shared Cloudflare tunnel (config in `~/.cloudflared/m4tthew-apps-tunnel.yml`, run by the `com.matthewgoodwin.m4tthew-apps-tunnel` launchd service) carries a wildcard ingress routing `*.m4tthew.dev` to the local-apps gateway on localhost:7950, which resolves the subdomain against the portless alias table. Registering an alias is therefore all it takes ... no per-app tunnel, DNS route, or tunnel plist.

IMPORTANT ... this means `portless alias` makes an app *reachable* on the internet, but the local-apps gateway (the `local-apps` project, which owns :7950) now gates every public request: an app is only served publicly when its publish toggle is on, and behind a password if one is set. New aliases default to published. Manage this from the local-apps dashboard (`apps.localhost`). If the app serves anything private, tell the user they can unpublish it or set a password there.

## Information to gather

Before doing anything, determine these values. Ask the user only for what you cannot infer from the project.

| Field | How to infer | Fallback |
|---|---|---|
| **app_name** | Directory name or package.json `name` | Ask |
| **domain** | `{app_name}.localhost` | Ask if ambiguous |
| **port** | Look for PORT in `.env`, `server.ts`, `package.json` scripts | Pick next unused port (see step 1) |
| **working_dir** | Current working directory | Ask |
| **entry_command** | Detect runtime: `bun` -> `bun src/server.ts` or `bun run start`; `node` -> `node src/server.js`; `deno` -> `deno run -A src/server.ts`. Check `package.json` scripts for a `start` or `dev` script. | Ask |
| **env_vars** | At minimum `PORT`. Scan `.env` for non-secret vars needed at runtime. Never put secrets in the plist -- use `.env` file loading in the app. | `PORT` only |
| **ok to be public?** | Aliased apps are public at `<name>.m4tthew.dev` automatically. Flag it if the app looks private (auth-less admin UI, personal data) | Assume public is fine for shareable apps |

If the app serves a built frontend only when a `dist`/`build` dir exists (common with Vite), run the production build first (`bun run build` or equiv) so launchd serves real assets, not just the API.

## Steps

### 1. Pick a port

Managed local apps use the `11000..11999` range (uniform, and clear of common dev
ports like 3000/5173/8080). Prefer the local-apps board's suggestion, which is the
lowest free port in range:

```bash
curl -s http://apps.localhost/api/status | grep -o '"nextPort":[0-9]*'
```

If the board is unreachable, pick the lowest free `11xxx` port yourself by checking
both sources:

```bash
portless list
ls ~/Library/LaunchAgents/com.matthewgoodwin.*.plist
```

If the project already pins a port in `.env` or source and you are not migrating it,
keep that port; otherwise allocate from `11000` upward.

### 2. Create logs directory

```bash
mkdir -p {working_dir}/logs
```

Add `logs/` to `.gitignore` if a git repo and not already ignored.

### 3. Create the launchd plist

Write to `~/Library/LaunchAgents/com.matthewgoodwin.{app_name}.plist`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.matthewgoodwin.{app_name}</string>
    <key>ProgramArguments</key>
    <array>
        <!-- Use full path to runtime binary -->
        <string>/Users/matt/.bun/bin/bun</string>
        <string>{entry_file}</string>
    </array>
    <key>WorkingDirectory</key>
    <string>{working_dir}</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PORT</key>
        <string>{port}</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>{working_dir}/logs/server.out.log</string>
    <key>StandardErrorPath</key>
    <string>{working_dir}/logs/server.err.log</string>
</dict>
</plist>
```

`{entry_file}` is relative to `WorkingDirectory` (e.g. `server/index.ts`). Adapt `ProgramArguments` based on the runtime:
- **Bun**: `/Users/matt/.bun/bin/bun {entry_file}`
- **Node (via volta)**: `/Users/matt/.volta/bin/node {entry_file}`
- **Shell script**: `/bin/zsh -i -l -c "{working_dir}/start-server.sh"` (use this when the app needs environment setup that a login shell provides, like volta shims or nvm)

### 4. Register the portless route

The subcommand is `alias` (registers a static route to a port portless doesn't manage):

```bash
portless alias {app_name} {port}
```

This registers `https://{app_name}.localhost -> 127.0.0.1:{port}`. Pass the bare name, not the full `.localhost` domain.

IMPORTANT ... the portless proxy runs as a persistent root service on port 443 (`portless service install`). A newly-registered alias is written to config but the running proxy keeps a stale in-memory route table, so the new domain 404s ("No app registered for ...") until the proxy is restarted. Restarting needs sudo, which an agent cannot do non-interactively ... have the user run:

```bash
sudo portless proxy stop -p 443 && portless proxy start
```

(You can confirm whether a restart is still needed: if `https://{app_name}.localhost` returns a portless 404 page whose "Active apps" list omits the new app, the proxy hasn't reloaded yet.)

### 5. Load the service

```bash
launchctl load ~/Library/LaunchAgents/com.matthewgoodwin.{app_name}.plist
```

### 6. Health check

Wait ~3 seconds. Check the app directly first (isolates app health from proxy state), then the domain:

```bash
curl -sf http://localhost:{port}/ -o /dev/null && echo "app OK" || echo "app FAILED"
curl -s -o /dev/null -w "%{http_code}\n" https://{app_name}.localhost/
```

`launchctl list | grep {app_name}` should show the service with exit status `0`. If the app fails, check logs:

```bash
tail -20 {working_dir}/logs/server.err.log
```

If the domain 404s but the direct port is healthy, the proxy needs the sudo restart from step 4.

### 7. Verify the public URL

The wildcard tunnel makes the app public as soon as the alias is registered. Just confirm:

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://{app_name}.m4tthew.dev/
```

A 200 means done. If it fails but the `.localhost` domain works, check that the shared tunnel is up (`launchctl list | grep tunnel` -> `com.matthewgoodwin.m4tthew-apps-tunnel`) and that `~/.cloudflared/m4tthew-apps-tunnel.yml` still carries the `*.m4tthew.dev` -> `http://localhost:7950` ingress. If the domain returns a "nothing here" 404, the app may just be unpublished in the local-apps dashboard (`apps.localhost`) -- toggle it public there.

#### Fallback: dedicated tunnel (only for apps NOT aliased in portless)

An app that bypasses portless (e.g. barn on its own port) needs its own named tunnel. Skip this entire section for anything registered with `portless alias`.

1. **Create the tunnel** (writes a `<uuid>.json` credentials file into `~/.cloudflared/`):

   ```bash
   /opt/homebrew/bin/cloudflared tunnel create {app_name}
   ```

   Note the tunnel UUID it prints.

2. **Write the config** to `~/.cloudflared/{app_name}.yml`:

   ```yaml
   tunnel: {uuid}
   credentials-file: /Users/matt/.cloudflared/{uuid}.json

   ingress:
     - hostname: {app_name}.m4tthew.dev
       service: http://localhost:{port}
     - service: http_status:404
   ```

3. **Route DNS** (creates the CNAME in the m4tthew.dev zone):

   ```bash
   /opt/homebrew/bin/cloudflared tunnel route dns {app_name} {app_name}.m4tthew.dev
   ```

4. **Create the tunnel launchd plist** at `~/Library/LaunchAgents/com.matthewgoodwin.{app_name}-tunnel.plist` so the tunnel auto-starts and stays up:

   ```xml
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
       <key>Label</key>
       <string>com.matthewgoodwin.{app_name}-tunnel</string>
       <key>ProgramArguments</key>
       <array>
           <string>/opt/homebrew/bin/cloudflared</string>
           <string>tunnel</string>
           <string>--config</string>
           <string>/Users/matt/.cloudflared/{app_name}.yml</string>
           <string>run</string>
           <string>{app_name}</string>
       </array>
       <key>RunAtLoad</key>
       <true/>
       <key>KeepAlive</key>
       <true/>
       <key>StandardOutPath</key>
       <string>{working_dir}/logs/tunnel.out.log</string>
       <key>StandardErrorPath</key>
       <string>{working_dir}/logs/tunnel.err.log</string>
   </dict>
   </plist>
   ```

5. **Load and verify:**

   ```bash
   launchctl load ~/Library/LaunchAgents/com.matthewgoodwin.{app_name}-tunnel.plist
   sleep 3
   curl -sf https://{app_name}.m4tthew.dev/ -o /dev/null && echo "public OK" || echo "public FAILED (DNS may take a moment)"
   ```

### 8. Report

Tell the user:
- The app is live at `https://{app_name}.m4tthew.dev` (public, shareable) and `https://{app_name}.localhost` (local)
- It auto-starts on login
- Logs are at `{working_dir}/logs/`
- If you added a portless alias, remind them to run the sudo proxy restart if the `.localhost` domain isn't resolving yet
- To restart the app: `launchctl unload ~/Library/LaunchAgents/com.matthewgoodwin.{app_name}.plist && launchctl load ~/Library/LaunchAgents/com.matthewgoodwin.{app_name}.plist`
- To stop permanently: `launchctl unload ~/Library/LaunchAgents/com.matthewgoodwin.{app_name}.plist`

## Updating an existing service

If the plist already exists, the user probably wants to restart after a config change:

```bash
launchctl unload ~/Library/LaunchAgents/com.matthewgoodwin.{app_name}.plist
launchctl load ~/Library/LaunchAgents/com.matthewgoodwin.{app_name}.plist
```

Same pattern for the `-tunnel` plist if the app is tunneled.

## Teardown

If asked to remove a service:

```bash
# Local service + route (removing the alias also removes the public {app_name}.m4tthew.dev URL)
launchctl unload ~/Library/LaunchAgents/com.matthewgoodwin.{app_name}.plist
rm ~/Library/LaunchAgents/com.matthewgoodwin.{app_name}.plist
portless alias --remove {app_name}

# Dedicated tunnel, only if the app had one (non-aliased apps)
launchctl unload ~/Library/LaunchAgents/com.matthewgoodwin.{app_name}-tunnel.plist
rm ~/Library/LaunchAgents/com.matthewgoodwin.{app_name}-tunnel.plist
/opt/homebrew/bin/cloudflared tunnel route dns --overwrite-dns {app_name} {app_name}.m4tthew.dev  # or delete the DNS record in the dashboard
/opt/homebrew/bin/cloudflared tunnel delete {app_name}
rm ~/.cloudflared/{app_name}.yml
```
