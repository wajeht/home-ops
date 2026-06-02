#!/bin/sh
# qBittorrent writes a single-instance lockfile containing the container's
# hostname. Because qbittorrent runs network_mode: service:gluetun, it gets a
# fresh hostname on every recreate, so QLockFile can never reclaim a lock left
# behind by an unclean stop — qbit then loops on "termination initiated" and
# the WebUI never binds 8085. Clear any stale lock before qbit starts so each
# container boots clean.
rm -f /config/qBittorrent/lockfile
