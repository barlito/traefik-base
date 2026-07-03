# fail2ban — host-level IP banning

Bans abusive IPs (SSH brute-force, HTTP scanners, and — later — game-server
abuse) at the **host** level, so a single ban covers every service at once.

## Why it runs outside Swarm, with a baked image

fail2ban needs `network_mode: host` + `NET_ADMIN` to see real client IPs and
edit the host routing table. Swarm services support neither, so — like WireGuard
— it runs as a standalone Compose stack (`docker-compose.fail2ban.yml`).

Because it isn't a Swarm service, it **can't use Swarm configs** (the mechanism
Traefik/Authelia use). And since we deploy from GitHub Actions over
`DOCKER_HOST=ssh` (no repo files ever land on the server), the jail + filter are
**baked into a custom image** (`fail2ban/Dockerfile`) built and pushed to GHCR
by CI. The server only pulls & runs it. Only the ban database is persisted, on
the `fail2ban_db` named volume at `/data/db`.

## How a ban is enforced: blackhole route

The ban action is `route`: `ip route add unreachable <ip>` in the host network
namespace. It drops the offender at the **routing layer**, before the
iptables/Docker DNAT path — so it blocks host processes (sshd) and containers
(Traefik, game servers) uniformly. A plain `iptables` INPUT rule would be
bypassed for container-bound traffic (Docker DNATs it through FORWARD).
Trade-off: all-or-nothing per IP (no per-port granularity).

> Prerequisite: Traefik must publish its ports in **host mode** (see
> `docker-compose.yml`). In ingress mode the Swarm mesh SNATs every connection
> to `10.0.0.2`, so fail2ban would only ever see — and try to ban — the mesh IP.

## Jails & policy

Everything is in a single `fail2ban/jail.d/jail.local`:

| Jail | Source | Bans |
|------|--------|------|
| `sshd` | `/var/log/auth.log` | SSH auth brute-force (built-in filter) |
| `traefik-badbots` | `/var/log/traefik/access.log` | IPs generating many HTTP 4xx |
| `minecraft` *(commented template)* | game server log | example for later |

Global policy: 5 strikes / 10 min → 1 h ban, doubling on each repeat up to
**30 days**. `ignoreip` covers localhost and the WireGuard subnet.

## Access log plumbing

Traefik's access log is switched from stdout to `/var/log/traefik/access.log`
(`accessLog.filePath` in `traefik.prod.yml`), a host bind mount shared read-only
with fail2ban. Traefik's **application** log stays on stdout for Alloy. To keep
access logs in Loki, point Alloy at the file (`loki.source.file`).

## Deploy

1. **Build the image** (once, and whenever `fail2ban/` changes): run the
   **Build fail2ban image** workflow (or `make fail2ban-build` + push).
   After the first push, set the GHCR package
   `ghcr.io/barlito/traefik-base-fail2ban` to **public** so the server can pull
   it without credentials.
2. **Deploy**: run the **Deploy fail2ban** workflow, or `make fail2ban-up`.

## Usage

```bash
make fail2ban-up       # pull + start
make fail2ban-status   # jails + currently banned IPs
make fail2ban-logs     # follow logs
make fail2ban-test     # dry-run the Traefik filter against the real log
make fail2ban-down     # stop
```

**Validate the HTTP filter before trusting it.** The Traefik log is JSON;
confirm the regex/datepattern in `filter.d/traefik-badbots.conf` with
`make fail2ban-test` (expect a non-zero match count once scanners have hit the
server).

Manually unban:

```bash
docker exec fail2ban fail2ban-client set traefik-badbots unbanip 1.2.3.4
```

## Adding a game server (e.g. Minecraft)

1. add `fail2ban/filter.d/minecraft.conf` (match the client IP in the server log)
2. uncomment the `[minecraft]` jail in `jail.local`, fix `logpath`, `enabled = true`
3. mount the server log into the fail2ban container (`docker-compose.fail2ban.yml`)
4. rebuild the image, then `make fail2ban-test`
