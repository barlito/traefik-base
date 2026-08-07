# Custom Falco image with our config + custom rules baked in.
#
# Rationale (same as fail2ban): this stack deploys to the server from GitHub
# Actions over DOCKER_HOST=ssh, so NO repo files ever land on the host — only
# running containers. Falco can't be a Swarm service (it needs host kernel
# access / elevated privileges for eBPF), so it can't use Swarm configs like
# Traefik/Authelia. Baking the config + rules into the image is how we ship
# them: the config travels INSIDE the image, the server only pulls & runs it.
#
# Driver: modern eBPF (CO-RE) — the probe is compiled into the Falco binary, so
# there is nothing to build against the host kernel and no headers are needed.
# Since 0.41 the default `falcosecurity/falco` image IS the slim one (the old
# `falco-no-driver` tag is gone; kmod/legacy-eBPF tooling moved to separate
# images). Requires a host kernel >= 5.8 with BTF enabled.
FROM falcosecurity/falco:0.44.1

# Main config: engine.kind=modern_ebpf + container plugin + JSON alerts on
# stdout. Replaces the stock /etc/falco/falco.yaml entirely (self-contained,
# config.d is not loaded — see config_files in falco.yaml).
COPY falco.yaml /etc/falco/falco.yaml

# Custom rules, loaded on top of the stock rule sets. rules.d/ is referenced by
# `rules_files` in falco.yaml.
COPY rules.d/ /etc/falco/rules.d/
