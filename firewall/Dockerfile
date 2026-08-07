# Host + container firewall — tiny alpine image running apply-firewall.sh.
#
# Rationale (same as fail2ban/falco): this stack deploys from GitHub Actions
# over DOCKER_HOST=ssh, so NO repo files ever land on the host — only running
# containers. The firewall needs the HOST network namespace + NET_ADMIN
# (docker-compose.firewall.yml), which Swarm services don't support, so it is
# a standalone container with its ruleset baked in.
#
# Both iptables backends (nft + legacy) are shipped; the script picks the one
# dockerd actually uses by looking for the DOCKER chain.
FROM alpine:3.22

RUN apk add --no-cache iptables

COPY apply-firewall.sh /apply-firewall.sh
RUN chmod +x /apply-firewall.sh

ENTRYPOINT ["/apply-firewall.sh"]
