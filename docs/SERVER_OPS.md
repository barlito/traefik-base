# Server ops cheatsheet — verify the security stack from SSH

Everything on the server is a container — no repo, no Makefile, no config
files on disk. All commands below run **directly on the server** (or from
your workstation with `export DOCKER_HOST=ssh://<user>@51.68.154.52:3333`).

## Firewall

```bash
# Is it running, and what did it apply?
docker ps --filter name=firewall
docker logs firewall --tail 20

# Live chains + per-rule packet counters (the `pkts` column tells you which
# rules actually match traffic — the final DROP counter = blocked scans)
docker exec firewall iptables-nft -L BARLITO-FW-INPUT -v -n     # host (INPUT)
docker exec firewall iptables-nft -L BARLITO-FW-DOCKER -v -n    # containers (DOCKER-USER)
# (if the chains are empty there, the host is on the legacy backend:
#  swap iptables-nft for iptables-legacy)

# Watch drops in real time (kernel log, rate-limited 5/min)
dmesg -wT | grep FW-DROP                 # FW-DROP-HOST: / FW-DROP-DOCKER:
journalctl -kf | grep FW-DROP            # same, via journald

# Verify the jumps are attached (should print one line each)
docker exec firewall iptables-nft -S INPUT | grep BARLITO
docker exec firewall iptables-nft -S DOCKER-USER | grep BARLITO

# Force an immediate re-apply (instead of waiting the 60s loop)
docker restart firewall

# EMERGENCY: remove all firewall rules (host back to Docker defaults)
docker run --rm --network host --cap-add NET_ADMIN --cap-add NET_RAW \
  -e FLUSH=1 ghcr.io/barlito/traefik-base-firewall:latest
```

From the outside (your machine at home, **not** through the VPN):

```bash
nmap -p 80,443,3333,5432 51.68.154.52   # expect: 80,443,3333 open, rest filtered
sudo nmap -sU -p 444,51820 51.68.154.52 # expect: open|filtered (UDP answers little)
```

## fail2ban — banned IPs

```bash
# Overview: jails + counts
docker exec fail2ban fail2ban-client status

# Detail per jail (currently banned IPs + totals)
docker exec fail2ban fail2ban-client status traefik-badbots
docker exec fail2ban fail2ban-client status sshd

# All banned IPs across all jails, one shot
docker exec fail2ban fail2ban-client banned

# The bans as the kernel sees them (blackhole routes — fail2ban shares the
# host network namespace, so this is the host routing table)
docker exec fail2ban ip route | grep unreachable

# Unban
docker exec fail2ban fail2ban-client set traefik-badbots unbanip 1.2.3.4
docker exec fail2ban fail2ban-client unban --all

# What is it matching right now? (dry-run the HTTP filter on the real log)
docker exec fail2ban fail2ban-regex /var/log/traefik/access.log \
  /data/filter.d/traefik-badbots.conf

# Activity log (bans/unbans as they happen)
docker logs -f fail2ban
```

## Falco — runtime alerts

```bash
docker ps --filter name=falco            # healthcheck status visible here
docker logs falco --tail 50              # JSON alerts, one per line
docker logs falco 2>&1 | grep -E '"priority":"(Critical|Error)"'
```

(Long-term the alerts land in Loki via Alloy — query
`{container="falco"}` in Grafana.)

## Quick health sweep

```bash
docker ps --format 'table {{.Names}}\t{{.Status}}'   # everything Up / healthy?
docker service ls                                    # Swarm side (traefik stack)
docker exec firewall iptables-nft -L BARLITO-FW-DOCKER -v -n | tail -2   # drops counting up = firewall working
docker exec fail2ban fail2ban-client banned                              # anyone in jail?
```
