# docker-opencode

A Docker image that runs [OpenCode](https://opencode.ai) — an AI coding assistant — with automatic secrets injection via [Vaultwarden](https://github.com/dani-garcia/vaultwarden) / Bitwarden. GitHub credentials are pulled from the vault at startup and wired into both the `gh` CLI and `git`, so OpenCode has full repository access with no secrets baked into the image.

**Image:** `ghcr.io/thomas-lg/docker-opencode:latest`

---

## Features

- **Vaultwarden/Bitwarden secrets integration** — vault credentials are the only secrets you pass to the container; everything else is fetched at runtime
- **Automatic GitHub authentication** — a vault entry named `"GitHub Token"` is used to log in `gh` and configure a `git` credential helper
- **Docker CLI access** — the Docker client is installed; connect it to your host via a socket proxy
- **GitHub CLI (`gh`)** and **Bitwarden CLI (`bw`)** included out of the box
- **Unraid-ready** — ships an official Community Apps XML template
- **Auto-published images** — tagged `latest`, semver, and short SHA via GitHub Actions on every push to `main`

---

## Prerequisites

- A running [Vaultwarden](https://github.com/dani-garcia/vaultwarden) or Bitwarden instance
- A vault item with the **exact name** `GitHub Token` whose **password** field contains a GitHub personal access token (with at minimum `repo` scope)
- A Bitwarden API key (`clientid` + `clientsecret`) for the account that owns the vault

> **Without Vaultwarden:** If you omit the `BW_*` variables, the container will still start OpenCode, but GitHub authentication will not be configured. You can supply a `GITHUB_TOKEN` environment variable and handle `gh auth` / git credentials yourself.

---

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `BW_SERVER_URL` | No | URL of a self-hosted Vaultwarden instance (e.g. `https://vault.example.com`). Omit to use `bitwarden.com`. |
| `BW_CLIENTID` | Yes* | Bitwarden API key client ID |
| `BW_CLIENTSECRET` | Yes* | Bitwarden API key client secret |
| `BW_PASSWORD` | Yes* | Master password used to unlock the vault |
| `DOCKER_HOST` | No | Docker daemon socket (e.g. `tcp://dockersocket:2375` via a socket proxy) |

\* Required for Vaultwarden secrets injection. Optional if you skip vault integration.

---

## Usage

### Docker Run

```bash
docker run -it --rm \
  -e BW_SERVER_URL=https://vault.example.com \
  -e BW_CLIENTID=user.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  -e BW_CLIENTSECRET=your-client-secret \
  -e BW_PASSWORD=your-master-password \
  -v /path/to/your/project:/root/workspace \
  -v opencode-config:/root/.config/opencode \
  -v opencode-data:/root/.local/share/opencode \
  ghcr.io/thomas-lg/docker-opencode:latest
```

To run the web UI (accessible at `http://localhost:4096`):

```bash
docker run -d \
  -e BW_SERVER_URL=https://vault.example.com \
  -e BW_CLIENTID=user.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx \
  -e BW_CLIENTSECRET=your-client-secret \
  -e BW_PASSWORD=your-master-password \
  -p 4096:4096 \
  -v /path/to/your/project:/root/workspace \
  -v opencode-config:/root/.config/opencode \
  -v opencode-data:/root/.local/share/opencode \
  ghcr.io/thomas-lg/docker-opencode:latest \
  web --hostname 0.0.0.0 --port 4096
```

### Docker Compose

```yaml
services:
  opencode:
    image: ghcr.io/thomas-lg/docker-opencode:latest
    environment:
      BW_SERVER_URL: https://vault.example.com
      BW_CLIENTID: user.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
      BW_CLIENTSECRET: your-client-secret
      BW_PASSWORD: your-master-password
      DOCKER_HOST: tcp://dockersocket:2375
    ports:
      - "4096:4096"
    volumes:
      - /path/to/your/workspace:/root/workspace
      - opencode-config:/root/.config/opencode
      - opencode-data:/root/.local/share/opencode
      - opencode-state:/root/.local/state/opencode
    command: web --hostname 0.0.0.0 --port 4096
    depends_on:
      - dockersocket

  # Socket proxy — avoids exposing the raw Docker socket to the container
  dockersocket:
    image: lscr.io/linuxserver/socket-proxy:latest
    environment:
      CONTAINERS: 1
      POST: 1
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
    restart: unless-stopped

volumes:
  opencode-config:
  opencode-data:
  opencode-state:
```

Store secrets in a `.env` file (already git-ignored) and reference it with `env_file: .env` or pass via `docker compose --env-file .env up`.

---

## Volumes

| Container path | Purpose |
|---|---|
| `/root/workspace` | Your project files / working directory |
| `/root/.config/opencode` | OpenCode configuration |
| `/root/.local/share/opencode` | OpenCode sessions and data |
| `/root/.local/state/opencode` | OpenCode state |

---

## Unraid

An Unraid Community Apps template is included at [`unraid-template.xml`](./unraid-template.xml). It pre-configures port bindings, environment variables, and a Docker socket proxy.

---

## How It Works

On container start, `entrypoint.sh` runs the following sequence before handing off to OpenCode:

1. **Configure server** — if `BW_SERVER_URL` is set, points the Bitwarden CLI at your self-hosted instance
2. **Restore session** — checks `/tmp/bw-session` for a cached, still-valid vault session token
3. **Login + unlock** — if no valid session exists, logs in via API key, unlocks with master password (up to 3 retries), and caches the session token
4. **Inject GitHub token** — fetches the password of the `"GitHub Token"` vault item, logs in `gh`, and registers a `git-credential-vaultwarden` helper for `https://github.com`
5. **Start OpenCode** — `exec opencode "$@"` — all container arguments are forwarded directly

If any vault step fails, the container falls back and starts OpenCode without GitHub authentication.

---

## Image Tags

| Tag | Updated on |
|---|---|
| `latest` | Every push to `main` |
| `x.y.z` / `x.y` | Semver git tags (`v*`) |
| `<short-sha>` | Every build |

---

## License

See [LICENSE](./LICENSE) if present, or check the upstream [OpenCode license](https://opencode.ai).
