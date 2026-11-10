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
FW_IPV6="${FW_IPV6:-true}"                              # mirror the policy on IPv6 (ip6tables)

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

# --- IPv6 ---------------------------------------------------------------------
# The host has a public IPv6 address. dockerd's userland proxy listens on [::]
# for EVERY published port, so without a v6 ruleset each published port (a
# database published in host mode, the wings SFTP, ...) is reachable from the
# internet over IPv6 even though the v4 rules drop it. Same backend as v4.
IPT6="ip6tables-${IPT#iptables-}"
if [ "$FW_IPV6" = "true" ] && ! $IPT6 -S INPUT >/dev/null 2>&1; then
    echo "ℹ️  firewall: ${IPT6} unusable (IPv6 disabled on this host?) — IPv6 rules skipped"
    FW_IPV6=false
fi

flush() {
    $IPT -D INPUT -j "$IN_CHAIN" 2>/dev/null
    $IPT -D DOCKER-USER -j "$FW_CHAIN" 2>/dev/null
    $IPT -F "$IN_CHAIN" 2>/dev/null && $IPT -X "$IN_CHAIN" 2>/dev/null
    $IPT -F "$FW_CHAIN" 2>/dev/null && $IPT -X "$FW_CHAIN" 2>/dev/null
    # Always try v6 too (even with FW_IPV6=false): removes rules left by a
    # previous run that had it enabled.
    $IPT6 -D INPUT -j "$IN_CHAIN" 2>/dev/null
    $IPT6 -D DOCKER-USER -j "$FW_CHAIN" 2>/dev/null
    $IPT6 -F "$IN_CHAIN" 2>/dev/null && $IPT6 -X "$IN_CHAIN" 2>/dev/null
    $IPT6 -F "$FW_CHAIN" 2>/dev/null && $IPT6 -X "$FW_CHAIN" 2>/dev/null
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

# $1 = iptables binary (v4 or v6), $2 = chain, $3 = log prefix
log_and_drop() {
    ipt="$1" chain="$2" prefix="$3"
    if [ "$FW_LOG_DROPS" = "true" ]; then
        $ipt -A "$chain" -m limit --limit 5/min --limit-burst 10 \
             -j LOG --log-prefix "$prefix" --log-level 4
    fi
    $ipt -A "$chain" -j DROP
}

# IPv6 mirror of the policy. Differences with v4:
#   - Published ports are filtered in INPUT, not only DOCKER-USER: Docker's
#     IPv6 NAT is off on the default networks, so v6 traffic to a published
#     port is NOT DNAT'ed — it is delivered locally to dockerd's userland proxy
#     and therefore traverses INPUT with the published port as dport.
#   - DOCKER-USER gets the same allowlist for the IPv6-enabled networks
#     (forwarded/DNAT'ed traffic, e.g. the pelican0 bridge).
#   - ICMPv6 is always accepted: neighbour discovery / router advertisements /
#     path-MTU run over it, dropping it kills IPv6 connectivity altogether.
#   - Private space is fc00::/7 (ULA, docker IPv6 networks) + fe80::/10
#     (link-local).
apply6() {
    $IPT6 -N "$IN_CHAIN" 2>/dev/null; $IPT6 -F "$IN_CHAIN"
    $IPT6 -N "$FW_CHAIN" 2>/dev/null; $IPT6 -F "$FW_CHAIN"

    # --- Host services + userland-proxied published ports (INPUT) ---
    $IPT6 -A "$IN_CHAIN" -i lo -j ACCEPT
    $IPT6 -A "$IN_CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    $IPT6 -A "$IN_CHAIN" -p ipv6-icmp -j ACCEPT
    $IPT6 -A "$IN_CHAIN" -m conntrack --ctstate INVALID -j DROP
    $IPT6 -A "$IN_CHAIN" -s fc00::/7  -j ACCEPT
    $IPT6 -A "$IN_CHAIN" -s fe80::/10 -j ACCEPT
    for ports in "$FW_HOST_ALLOW_TCP" "$FW_DOCKER_ALLOW_TCP"; do
        [ -n "$ports" ] && \
            $IPT6 -A "$IN_CHAIN" -p tcp -m multiport --dports "$ports" -j ACCEPT
    done
    for ports in "$FW_HOST_ALLOW_UDP" "$FW_DOCKER_ALLOW_UDP"; do
        [ -n "$ports" ] && \
            $IPT6 -A "$IN_CHAIN" -p udp -m multiport --dports "$ports" -j ACCEPT
    done
    log_and_drop "$IPT6" "$IN_CHAIN" "FW6-DROP-HOST: "

    # --- IPv6-enabled docker networks (DOCKER-USER) ---
    $IPT6 -A "$FW_CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
    $IPT6 -A "$FW_CHAIN" -p ipv6-icmp -j RETURN
    $IPT6 -A "$FW_CHAIN" -m conntrack --ctstate INVALID -j DROP
    $IPT6 -A "$FW_CHAIN" -s fc00::/7  -j RETURN
    $IPT6 -A "$FW_CHAIN" -s fe80::/10 -j RETURN
    for p in $(echo "$FW_DOCKER_ALLOW_TCP" | tr ',' ' '); do
        $IPT6 -A "$FW_CHAIN" -p tcp -m conntrack --ctdir ORIGINAL --ctorigdstport "$p" -j RETURN
    done
    for p in $(echo "$FW_DOCKER_ALLOW_UDP" | tr ',' ' '); do
        $IPT6 -A "$FW_CHAIN" -p udp -m conntrack --ctdir ORIGINAL --ctorigdstport "$p" -j RETURN
    done
    log_and_drop "$IPT6" "$FW_CHAIN" "FW6-DROP-DOCKER: "

    $IPT6 -N DOCKER-USER 2>/dev/null
    $IPT6 -C INPUT -j "$IN_CHAIN" 2>/dev/null || $IPT6 -I INPUT 1 -j "$IN_CHAIN"
    $IPT6 -C DOCKER-USER -j "$FW_CHAIN" 2>/dev/null || $IPT6 -I DOCKER-USER 1 -j "$FW_CHAIN"
}

# True when every jump rule we own is still attached.
attached() {
    $IPT -C INPUT -j "$IN_CHAIN" 2>/dev/null || return 1
    $IPT -C DOCKER-USER -j "$FW_CHAIN" 2>/dev/null || return 1
    if [ "$FW_IPV6" = "true" ]; then
        $IPT6 -C INPUT -j "$IN_CHAIN" 2>/dev/null || return 1
        $IPT6 -C DOCKER-USER -j "$FW_CHAIN" 2>/dev/null || return 1
    fi
    return 0
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
    log_and_drop "$IPT" "$IN_CHAIN" "FW-DROP-HOST: "

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
    log_and_drop "$IPT" "$FW_CHAIN" "FW-DROP-DOCKER: "

    # --- Attach (idempotent) ---
    # DOCKER-USER exists on any dockerd >= 17.06; create it if we somehow run
    # before the daemon.
    $IPT -N DOCKER-USER 2>/dev/null
    $IPT -C INPUT -j "$IN_CHAIN" 2>/dev/null || $IPT -I INPUT 1 -j "$IN_CHAIN"
    $IPT -C DOCKER-USER -j "$FW_CHAIN" 2>/dev/null || $IPT -I DOCKER-USER 1 -j "$FW_CHAIN"

    [ "$FW_IPV6" = "true" ] && apply6
    return 0
}

trap 'echo "⏹  firewall: stopping (rules stay in place — use FLUSH=1 to remove)"; exit 0' TERM INT

apply
echo "✅ firewall: rules applied (host tcp:[$FW_HOST_ALLOW_TCP] udp:[$FW_HOST_ALLOW_UDP] | docker tcp:[$FW_DOCKER_ALLOW_TCP] udp:[$FW_DOCKER_ALLOW_UDP] | vpn $FW_VPN_SUBNET | ipv6 $FW_IPV6)"

# Re-assert forever: cheap, and heals the attachment if dockerd restarted.
while :; do
    sleep "$FW_INTERVAL" &
    wait $!
    if ! attached; then
        echo "🔁 firewall: attachment lost (dockerd restart?) — re-applying"
        apply
    fi
done
