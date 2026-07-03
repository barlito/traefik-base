# Custom fail2ban image with our jail + filter baked in.
#
# Rationale: this stack deploys to Swarm from GitHub Actions over
# DOCKER_HOST=ssh, so NO repo files ever land on the server — only running
# containers. fail2ban can't be a Swarm service (it needs host networking for
# the blackhole route ban), so it can't use Swarm configs like Traefik/Authelia.
# Baking the config into the image is the way to ship it: the config travels
# INSIDE the image, the server only pulls & runs it.
#
# The ban database is kept OUT of the image on a named volume mounted at
# /data/db (see docker-compose.fail2ban.yml), which does not shadow the baked
# /data/jail.d and /data/filter.d.
FROM crazymax/fail2ban:1.1.0

COPY jail.d/ /data/jail.d/
COPY filter.d/ /data/filter.d/
