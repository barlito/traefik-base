# Falco — runtime threat detection

[Falco](https://falco.org/) watches the kernel's **syscalls** (via eBPF) and
raises an alert when a container or the host does something suspicious: a shell
opened inside a container, a sensitive file read, a privilege escalation, a
write to a system binary, an unexpected outbound connection…

Falco **only alerts — it never bans**. It is a **detection** layer,
complementary to [fail2ban](FAIL2BAN.md), which does the actual IP banning.
Think of it as an IDS for the host and its containers.

## Why it runs outside Swarm, with a baked image

The modern eBPF probe needs host kernel access and elevated privileges, which
`docker stack deploy` services do not support. So — like WireGuard and fail2ban
— Falco runs as a standalone Compose stack (`docker-compose.falco.yml`).

Because it isn't a Swarm service, it **can't use Swarm configs** (the mechanism
Traefik/Authelia use). And since we deploy from GitHub Actions over
`DOCKER_HOST=ssh` (no repo files ever land on the server), `falco.yaml` and the
custom rules are **baked into a custom image** (`falco/Dockerfile`) built and
pushed to GHCR by CI. The server only pulls & runs it.

## Driver: modern eBPF (CO-RE)

We use the **modern eBPF** engine (`engine.kind: modern_ebpf`). The probe is
compiled **into the Falco binary** (CO-RE), so there is **no kernel module to
build** and no kernel headers needed on the host. Since Falco 0.41 the default
`falcosecurity/falco` image is that slim, driver-less image (the old
`falco-no-driver` tag no longer exists).

Since Falco 0.44, the `container.*` fields (name, image…) in alerts come from
the **container plugin**, configured in our `falco.yaml` (`load_plugins` +
`plugins:` block) against the Docker socket mounted under `/host`. Socket
paths in the plugin config are given WITHOUT the `/host` prefix — the plugin
prepends `HOST_ROOT` itself.

> **Prerequisite:** the host kernel must be **>= 5.8 with BTF enabled**. The OVH
> host must satisfy this — verify with `uname -r` and
> `ls /sys/kernel/btf/vmlinux`. If BTF is missing, either upgrade the kernel or
> switch to the legacy eBPF/kmod driver (`falcosecurity/falco` image + driver
> loader), which this stack deliberately avoids.

The container runs `privileged: true` + `pid: host` (the most robust setup) and
mounts host state read-only under `/host` (`/proc`, `/etc`, `/boot`,
`/lib/modules`, `/dev`, and the Docker socket for container metadata). The
tighter alternative — dropping `privileged` for
`cap_add: [SYS_BPF, SYS_PERFMON, SYS_RESOURCE, SYS_PTRACE]` — is noted inline in
the compose file.

## Alerting: JSON on stdout → Loki

Falco is configured with `json_output: true` and `stdout_output.enabled: true`,
so every alert is one JSON object per line on stdout. The
[observability-stack](https://github.com/barlito/observability-stack) Alloy
agent already scrapes every container's stdout into Loki, so Falco alerts land
there **with no extra moving part**. Query them in Grafana, e.g.
`{container="falco"} | json | priority="Warning"`.

### Future evolution: Falcosidekick

For richer routing (Slack, generic webhook, PagerDuty, dedup, a UI), the usual
next step is [Falcosidekick](https://github.com/falcosecurity/falcosidekick):
add it as a second container, point Falco's `http_output` at it
(`http_output.url: http://falcosidekick:2801`), and configure the outputs there.
Not wired up now — stdout → Loki is enough to start.

## Rules

Falco loads its **stock rule sets** (`falco_rules.yaml`,
`falco_rules.local.yaml`) plus our custom rules in
`falco/rules.d/custom-rules.yaml` (baked in, referenced by `rules_files`):

| Rule | Priority | Fires when |
|------|----------|------------|
| `Interactive shell in a Barlito container` | WARNING | an interactive shell (bash/sh/…) with a TTY is executed inside a container (manual debug or intrusion) |
| `Package manager run in a Barlito container` | ERROR | apt/apk/pip/… runs inside a container — images are built in CI, runtime installs are never expected |
| `Traefik ACME store read by another process` | CRITICAL | anything other than the `traefik` binary reads `acme.json` (all the stack's TLS private keys) |
| `Docker socket accessed by unexpected container` | CRITICAL | a container not on the allowlist (socket-proxy, falco, alloy) opens the Docker socket — e.g. it was started with the socket bind-mounted |
| `Outbound connection from docker-socket-proxy` | CRITICAL | the socket-proxy initiates an outbound network connection (it should only accept inbound + talk to the unix socket) |
| `Sensitive credential file read in a Barlito container` | WARNING | a container process reads SSH keys, `/etc/shadow`, or cloud credentials |

Notes:

- Falco only fires the **first** matching rule per event (`rule_matching:
  first`); the stock `Terminal shell in container` rule is disabled in our
  file so that our shell rule (with container/image fields) wins.
- The Docker-socket rule matches `open*` only, **not** `connect()`: Falco's
  unix-socket name resolution returns stale names (kernel struct reuse),
  which floods the rule with false positives from FrankenPHP worker sockets.
  Opening covers the realistic vector — `runc` opening the socket when a
  container starts with it bind-mounted.

Keep the file high-signal — noisy rules drown real alerts.

## Deploy

1. **Build the image** (once, and whenever `falco/` changes): run the
   **Build Falco image** workflow (or `make falco-build` + push).
   After the first push, set the GHCR package
   `ghcr.io/barlito/traefik-base-falco` to **public** so the server can pull it
   without credentials.
2. **Deploy**: run the **Deploy Falco** workflow, or `make falco-up`.

## Usage

```bash
make falco-build   # build the image locally (validates Dockerfile + config)
make falco-up      # pull + start
make falco-logs    # follow alerts (JSON on stdout)
make falco-down    # stop
```

Trigger a test alert once running:

```bash
# opens a shell in the Falco container itself → "Interactive shell in a Barlito container"
docker exec -it falco bash
```

## Adding a custom rule

1. add the rule (and any macros/lists) to `falco/rules.d/custom-rules.yaml`
2. rebuild the image (`make falco-build`) and validate against the **full** rule
   set (the custom file relies on stock macros like `spawned_process`, so it
   won't validate on its own):
   ```bash
   docker run --rm --entrypoint falco ghcr.io/barlito/traefik-base-falco:latest \
     -c /etc/falco/falco.yaml \
     --validate /etc/falco/falco_rules.yaml \
     --validate /etc/falco/falco_rules.local.yaml \
     --validate /etc/falco/rules.d/custom-rules.yaml
   ```
3. run the **Build Falco image** then **Deploy Falco** workflows
