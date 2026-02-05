#!/bin/bash
# Adds /dev/dri device access to Plex container in Docker Swarm
# Workaround for Docker Swarm not supporting --device flag
#
# /dev/dri/card0 = 226:0
# /dev/dri/renderD128 = 226:128

CONTAINER_NAME="media_plex"

add_device_access() {
    local container_id=$1

    # Get the cgroup path for this container
    local cgroup_path

    # Try cgroups v2 first
    if [ -f "/sys/fs/cgroup/system.slice/docker-${container_id}.scope/cgroup.controllers" ]; then
        # cgroups v2 uses BPF, more complex - fall back to devices.allow if available
        cgroup_path="/sys/fs/cgroup/system.slice/docker-${container_id}.scope"
    fi

    # Try cgroups v1
    local cgroup_v1_path="/sys/fs/cgroup/devices/docker/${container_id}"
    if [ -d "$cgroup_v1_path" ]; then
        echo "Adding /dev/dri access to container $container_id (cgroups v1)"
        # Allow access to /dev/dri/card0 (226:0) and /dev/dri/renderD128 (226:128)
        echo "c 226:0 rwm" > "${cgroup_v1_path}/devices.allow" 2>/dev/null
        echo "c 226:128 rwm" > "${cgroup_v1_path}/devices.allow" 2>/dev/null
        echo "Device access granted"
        return 0
    fi

    # Try systemd cgroup path
    local systemd_path="/sys/fs/cgroup/devices/system.slice/docker-${container_id}.scope"
    if [ -d "$systemd_path" ]; then
        echo "Adding /dev/dri access to container $container_id (systemd cgroup)"
        echo "c 226:0 rwm" > "${systemd_path}/devices.allow" 2>/dev/null
        echo "c 226:128 rwm" > "${systemd_path}/devices.allow" 2>/dev/null
        echo "Device access granted"
        return 0
    fi

    echo "Warning: Could not find cgroup path for container $container_id"
    return 1
}

echo "Plex Hardware Acceleration Service Started"
echo "Monitoring for container: $CONTAINER_NAME"

# Check if plex is already running
existing_id=$(docker ps --filter "name=$CONTAINER_NAME" --format "{{.ID}}" 2>/dev/null | head -1)
if [ -n "$existing_id" ]; then
    echo "Found existing plex container: $existing_id"
    add_device_access "$existing_id"
fi

# Monitor docker events for container starts
docker events --filter "event=start" --format "{{.Actor.Attributes.name}} {{.Actor.ID}}" | while read name container_id; do
    if [[ "$name" == *"$CONTAINER_NAME"* ]] || [[ "$name" == *"plex"* ]]; then
        echo "Plex container started: $name ($container_id)"
        sleep 2  # Wait for container to fully initialize
        add_device_access "$container_id"
    fi
done
