# Firewall — host + container filtering

Default-deny firewall for the server, covering **both** traffic paths:

| Path | netfilter hook | What lives there |
|------|----------------|------------------|
| Host services | `INPUT` | sshd (3333), any daemon on the host itself |
| Published container ports | `DOCKER-USER` (called from `FORWARD`) | Traefik 80/443/444, WireGuard 51820, anything `ports:`-published |

## Why a host firewall alone doesn't work with Docker

Docker DNATs published ports in `PREROUTING`: the packets go host-interface →
`FORWARD` → container, and **never traverse `INPUT`**. A UFW/`iptables INPUT`
rule therefore silently does nothing for containers — the classic "UFW says
closed, `docker -p` says open" trap. The supported integration point for
filtering container-bound traffic is the
[`DOCKER-USER`](https://docs.docker.com/engine/network/packet-filtering-firewalls/)
chain, which dockerd guarantees to call first and never flushes. This firewall
attaches there for containers, and to `INPUT` for the host.

## Default policy

- **Fail-open, never fail-closed**: established connections are always
  accepted first (a bad apply can't cut the SSH session fixing it), and the
  chains are rebuilt in place under a permanent jump — worst case is a
  millisecond of Docker-default behaviour, never a lockout.
- **Host (`INPUT`)**: loopback, established, rate-limited ping, SSH
  `3333/tcp` → everything else from the internet **dropped**.
- **Containers (`DOCKER-USER`)**: `80,443/tcp` (Traefik), `444/udp` (HTTP/3),
  `51820/udp` (WireGuard) → every other **published port is dropped** from the
  internet. Publishing a port by mistake (a debug 5432, a forgotten admin
  UI) no longer exposes it.
- **VPN clients** (`10.8.0.0/24`) and **RFC1918 sources** (container-to-
  container on docker bridges/overlays, container-to-host) pass everything.
- Ports are matched with `--ctorigdstport` (the ORIGINAL pre-DNAT published
  port) — in `DOCKER-USER` the packets are already DNAT'ed, so a plain
  `--dport` would match the container-side port instead.

Dropped packets are logged to the kernel log (`FW-DROP-HOST:` /
`FW-DROP-DOCKER:` prefixes, rate-limited 5/min) — visible with
`dmesg | grep FW-DROP` on the host or via journal scraping.

## Why it runs outside Swarm, with a baked image

Same pattern as WireGuard / fail2ban / Falco: it needs the **host network
namespace + `NET_ADMIN`**, which Swarm services don't support, and we deploy
over `DOCKER_HOST=ssh` with no repo files on the server — so the ruleset is
baked into `ghcr.io/barlito/traefik-base-firewall` (built by CI) and the
server only pulls & runs it.

The script picks the iptables backend (`iptables-nft` vs `iptables-legacy`)
**matching dockerd** by looking for the `DOCKER` chain — writing rules into
the wrong backend would make them dead letters.

The container re-asserts the rules every 60 s (idempotent): if dockerd
restarts and re-plumbs its chains, the firewall heals itself within a minute.
Stopping the container **leaves the rules in place** (protection survives);
`make firewall-flush` actually removes them.

## Interaction with the rest of the stack

- **fail2ban** bans via blackhole *routes* — a different layer, fully
  independent. fail2ban bans specific offenders; the firewall closes whole
  ports.
- **WireGuard** keeps working: `51820/udp` is allowed in `DOCKER-USER`
  (wg-easy publishes it as a normal bridge port), and VPN clients are
  whitelisted everywhere.
- **Traefik host-mode ports** (80/443/444) also flow through
  `FORWARD`/`DOCKER-USER` (host mode changes the SNAT behaviour, not the DNAT
  path), so they are covered by the same allowlist.
- **Game servers later**: add the published port to `FW_DOCKER_ALLOW_TCP/UDP`
  in `docker-compose.firewall.yml`, `make firewall-build` + push, redeploy.

## Deploy

1. **Build the image** (once, and whenever `firewall/` changes): run the
   **Build firewall image** workflow (or `make firewall-build` + push).
   After the first push, set the GHCR package
   `ghcr.io/barlito/traefik-base-firewall` to **public**.
2. **Deploy**: run the **Deploy firewall** workflow, or `make firewall-up`
   with `DOCKER_HOST` pointing at the server.

Like fail2ban, the firewall only ever runs **on the server** — the `make`
targets act on whatever daemon your CLI points at.

## Usage

```bash
make firewall-up       # pull + start (rules applied immediately)
make firewall-status   # live chains + per-rule packet counters
make firewall-logs     # apply/re-assert log
make firewall-down     # stop the container — rules STAY
make firewall-flush    # remove the rules — host back to Docker defaults
```

Verify from outside (e.g. from home, NOT through the VPN):

```bash
nmap -p 80,443,3333,5432 <server-ip>   # expect: 80,443,3333 open, anything else filtered
```

## Configuration

Everything is an env var on the container (defaults in the script):

| Var | Default | Meaning |
|-----|---------|---------|
| `FW_HOST_ALLOW_TCP` | `3333` | host TCP ports open to the internet |
| `FW_HOST_ALLOW_UDP` | *(empty)* | host UDP ports open to the internet |
| `FW_DOCKER_ALLOW_TCP` | `80,443` | published TCP ports open to the internet |
| `FW_DOCKER_ALLOW_UDP` | `444,51820` | published UDP ports open to the internet |
| `FW_VPN_SUBNET` | `10.8.0.0/24` | trusted VPN clients |
| `FW_LOG_DROPS` | `true` | kernel-log dropped packets (rate-limited) |
| `FW_INTERVAL` | `60` | re-assert period in seconds |

IPv6 is deliberately not managed (Docker's IPv6 is disabled on this host; the
v4 rules cover the actual traffic). If the server ever serves AAAA records,
add an `ip6tables` pass — do NOT blanket-drop v6 `INPUT` before checking what
uses it, that's a remote-hands ticket waiting to happen.
