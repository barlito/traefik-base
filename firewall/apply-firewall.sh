#!/bin/sh
# Host + container firewall for the Barlito stack.
#
# Two attachment points, because Docker splits traffic in two paths:
#   - INPUT       -> traffic to HOST services (sshd on 3333, host daemons).
#   - DOCKER-USER -> traffic FORWARDed to containers (published ports are
#                    DNAT'ed in PREROUTING and never traverse INPUT — the
#                    reason UFW & co are silently bypassed by Docker).
#
# Design rules:
#   - Fail-open, never fail-closed: our chains are rebuilt in place and the
#     first rules always ACCEPT established connections — a bad apply can
#     never cut the SSH session that would fix it.
#   - Idempotent: safe to run every FW_INTERVAL seconds; re-asserts the
#     rules if dockerd recreated its chains after a restart.
#   - Ports in DOCKER-USER are matched with --ctorigdstport: by the time a
#     packet reaches FORWARD it is already DNAT'ed, so the visible dport is
#     the CONTAINER port, not the published one.
#
# FLUSH=1 removes everything this script ever added, then exits.
set -u

# --- Config (env, with defaults matching the stack) ---------------------------
FW_HOST_ALLOW_TCP="${FW_HOST_ALLOW_TCP:-3333}"          # sshd
FW_HOST_ALLOW_UDP="${FW_HOST_ALLOW_UDP:-}"              # (none: WG is a published port)
FW_DOCKER_ALLOW_TCP="${FW_DOCKER_ALLOW_TCP:-80,443}"    # Traefik HTTP/HTTPS
FW_DOCKER_ALLOW_UDP="${FW_DOCKER_ALLOW_UDP:-444,51820}" # HTTP/3 + WireGuard
FW_VPN_SUBNET="${FW_VPN_SUBNET:-10.8.0.0/24}"           # WireGuard clients: full access
FW_LOG_DROPS="${FW_LOG_DROPS:-true}"                    # kernel-log dropped packets (rate-limited)
FW_INTERVAL="${FW_INTERVAL:-60}"                        # re-assert period (seconds)

IN_CHAIN="BARLITO-FW-INPUT"
FW_CHAIN="BARLITO-FW-DOCKER"

# --- Pick the iptables backend dockerd actually uses --------------------------
# The host may be nft-based while alpine defaults to legacy (or vice-versa);
# writing rules into the wrong backend makes them dead letters. The DOCKER
# chain tells us where dockerd lives.
if iptables-nft -t nat -S DOCKER >/dev/null 2>&1; then
    IPT=iptables-nft
elif iptables-legacy -t nat -S DOCKER >/dev/null 2>&1; then
    IPT=iptables-legacy
else
    echo "⚠️  No DOCKER chain found in either iptables backend — defaulting to iptables-nft"
    IPT=iptables-nft
fi
echo "🔥 firewall: using ${IPT}"

flush() {
    $IPT -D INPUT -j "$IN_CHAIN" 2>/dev/null
    $IPT -D DOCKER-USER -j "$FW_CHAIN" 2>/dev/null
    $IPT -F "$IN_CHAIN" 2>/dev/null && $IPT -X "$IN_CHAIN" 2>/dev/null
    $IPT -F "$FW_CHAIN" 2>/dev/null && $IPT -X "$FW_CHAIN" 2>/dev/null
    echo "🧹 firewall: chains removed, host back to Docker defaults"
}

if [ "${FLUSH:-0}" = "1" ]; then
    flush
    exit 0
fi

# Append $1 (chain) rules shared by both attachment points; $2 is the verdict
# for "let it through" (ACCEPT in INPUT, RETURN in DOCKER-USER where the rest
# of Docker's chains must still run).
common_allows() {
    chain="$1" pass="$2"
    $IPT -A "$chain" -m conntrack --ctstate ESTABLISHED,RELATED -j "$pass"
    $IPT -A "$chain" -m conntrack --ctstate INVALID -j DROP
    # VPN clients get full access, and private ranges keep container-to-
    # container / container-to-host traffic working (docker bridges & overlay
    # networks all live in RFC1918 space).
    $IPT -A "$chain" -s "$FW_VPN_SUBNET" -j "$pass"
    $IPT -A "$chain" -s 10.0.0.0/8      -j "$pass"
    $IPT -A "$chain" -s 172.16.0.0/12   -j "$pass"
    $IPT -A "$chain" -s 192.168.0.0/16  -j "$pass"
}

log_and_drop() {
    chain="$1" prefix="$2"
    if [ "$FW_LOG_DROPS" = "true" ]; then
        $IPT -A "$chain" -m limit --limit 5/min --limit-burst 10 \
             -j LOG --log-prefix "$prefix" --log-level 4
    fi
    $IPT -A "$chain" -j DROP
}

apply() {
    # (Re)build our chains in place. The jump rules stay attached while the
    # chain is briefly empty -> empty chain RETURNs -> fail-open, no lockout.
    $IPT -N "$IN_CHAIN" 2>/dev/null; $IPT -F "$IN_CHAIN"
    $IPT -N "$FW_CHAIN" 2>/dev/null; $IPT -F "$FW_CHAIN"

    # --- Host services (INPUT) ---
    $IPT -A "$IN_CHAIN" -i lo -j ACCEPT
    common_allows "$IN_CHAIN" ACCEPT
    $IPT -A "$IN_CHAIN" -p icmp --icmp-type echo-request -m limit --limit 5/s -j ACCEPT
    [ -n "$FW_HOST_ALLOW_TCP" ] && \
        $IPT -A "$IN_CHAIN" -p tcp -m multiport --dports "$FW_HOST_ALLOW_TCP" -j ACCEPT
    [ -n "$FW_HOST_ALLOW_UDP" ] && \
        $IPT -A "$IN_CHAIN" -p udp -m multiport --dports "$FW_HOST_ALLOW_UDP" -j ACCEPT
    log_and_drop "$IN_CHAIN" "FW-DROP-HOST: "

    # --- Published container ports (DOCKER-USER) ---
    common_allows "$FW_CHAIN" RETURN
    # Match the ORIGINAL (pre-DNAT) published port. --ctorigdstport takes a
    # single port, hence the loop.
    for p in $(echo "$FW_DOCKER_ALLOW_TCP" | tr ',' ' '); do
        $IPT -A "$FW_CHAIN" -p tcp -m conntrack --ctdir ORIGINAL --ctorigdstport "$p" -j RETURN
    done
    for p in $(echo "$FW_DOCKER_ALLOW_UDP" | tr ',' ' '); do
        $IPT -A "$FW_CHAIN" -p udp -m conntrack --ctdir ORIGINAL --ctorigdstport "$p" -j RETURN
    done
    log_and_drop "$FW_CHAIN" "FW-DROP-DOCKER: "

    # --- Attach (idempotent) ---
    # DOCKER-USER exists on any dockerd >= 17.06; create it if we somehow run
    # before the daemon.
    $IPT -N DOCKER-USER 2>/dev/null
    $IPT -C INPUT -j "$IN_CHAIN" 2>/dev/null || $IPT -I INPUT 1 -j "$IN_CHAIN"
    $IPT -C DOCKER-USER -j "$FW_CHAIN" 2>/dev/null || $IPT -I DOCKER-USER 1 -j "$FW_CHAIN"
}

trap 'echo "⏹  firewall: stopping (rules stay in place — use FLUSH=1 to remove)"; exit 0' TERM INT

apply
echo "✅ firewall: rules applied (host tcp:[$FW_HOST_ALLOW_TCP] udp:[$FW_HOST_ALLOW_UDP] | docker tcp:[$FW_DOCKER_ALLOW_TCP] udp:[$FW_DOCKER_ALLOW_UDP] | vpn $FW_VPN_SUBNET)"

# Re-assert forever: cheap, and heals the attachment if dockerd restarted.
while :; do
    sleep "$FW_INTERVAL" &
    wait $!
    if ! $IPT -C INPUT -j "$IN_CHAIN" 2>/dev/null \
       || ! $IPT -C DOCKER-USER -j "$FW_CHAIN" 2>/dev/null; then
        echo "🔁 firewall: attachment lost (dockerd restart?) — re-applying"
        apply
    fi
done
