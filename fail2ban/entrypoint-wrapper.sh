#!/bin/sh
# Start busybox crond (hourly logrotate of the Traefik access log — see
# /etc/logrotate.d/traefik-access) alongside fail2ban, then hand over to the
# stock crazymax/fail2ban entrypoint. crond is a daemon: it forks and stays
# alive in the background; fail2ban-server remains PID 1's foreground child.
set -e

# Sync the baked config into /data (an anonymous volume that survives container
# recreation — see the Dockerfile). The image is the single source of truth for
# jail.d/ and filter.d/: stale files are removed. /data/db (ban database, named
# volume) is left untouched.
for d in jail.d filter.d; do
    mkdir -p "/data/$d"
    rm -f "/data/$d"/*
    cp /opt/fail2ban-config/"$d"/* "/data/$d/"
done

crond -L /dev/stdout

exec /entrypoint.sh "$@"
