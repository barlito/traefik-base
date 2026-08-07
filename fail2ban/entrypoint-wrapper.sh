#!/bin/sh
# Start busybox crond (hourly logrotate of the Traefik access log — see
# /etc/logrotate.d/traefik-access) alongside fail2ban, then hand over to the
# stock crazymax/fail2ban entrypoint. crond is a daemon: it forks and stays
# alive in the background; fail2ban-server remains PID 1's foreground child.
set -e

crond -L /dev/stdout

exec /entrypoint.sh "$@"
