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
# Hence the slim `falco-no-driver` base (no kmod/eBPF build toolchain). Requires
# a host kernel >= 5.8 with BTF enabled (the OVH host must satisfy this).
FROM falcosecurity/falco-no-driver:0.39.2

# Main config: engine.kind=modern_ebpf + JSON alerts on stdout.
COPY falco.yaml /etc/falco/falco.yaml

# Custom rules, loaded on top of the stock rule sets. rules.d/ is referenced by
# `rules_files` in falco.yaml.
COPY rules.d/ /etc/falco/rules.d/
