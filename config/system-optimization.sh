#!/bin/bash
# ============================================================================
# Nextcloud AIO System Optimization Script
# ============================================================================
# Run this on Ubuntu VM after migration completes
# Optimizes system for 16GB RAM / 12 vCPU / 64GB storage
# ============================================================================

set -e

echo "========================================="
echo "Nextcloud AIO System Optimization"
echo "========================================="
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
   echo "Please run as root (sudo)"
   exit 1
fi

# 1. System Kernel Parameters
echo "[1/5] Configuring system kernel parameters..."
tee /etc/sysctl.d/99-nextcloud-aio.conf > /dev/null <<EOF
# File system limits
fs.inotify.max_user_watches=524288
fs.inotify.max_user_instances=512
fs.inotify.max_queued_events=32768

# Network optimization
net.core.somaxconn=65535
net.ipv4.tcp_max_syn_backlog=8192
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_fin_timeout=30

# Memory management
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_ratio=10
vm.dirty_background_ratio=5
EOF

sysctl -p /etc/sysctl.d/99-nextcloud-aio.conf > /dev/null
echo "✓ Kernel parameters configured"

# 2. Docker Optimization
echo "[2/5] Optimizing Docker configuration..."
tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  },
  "live-restore": true,
  "userland-proxy": false
}
EOF

systemctl restart docker
sleep 5
echo "✓ Docker optimized and restarted"

# 3. Nextcloud PHP/Redis Optimization
echo "[3/5] Optimizing Nextcloud caching..."
docker exec -u www-data nextcloud-aio-nextcloud php occ config:system:set memcache.local --value='\\OC\\Memcache\\APCu' > /dev/null
docker exec -u www-data nextcloud-aio-nextcloud php occ config:system:set memcache.distributed --value='\\OC\\Memcache\\Redis' > /dev/null
docker exec -u www-data nextcloud-aio-nextcloud php occ config:system:set memcache.locking --value='\\OC\\Memcache\\Redis' > /dev/null
echo "✓ Caching configured (APCu + Redis)"

# 4. Background Jobs
echo "[4/5] Configuring background jobs..."
docker exec -u www-data nextcloud-aio-nextcloud php occ background:cron > /dev/null
echo "✓ Background jobs set to cron"

# 5. File Locking
echo "[5/5] Enabling file locking..."
docker exec -u www-data nextcloud-aio-nextcloud php occ config:system:set filelocking.enabled --value=true --type=boolean > /dev/null
echo "✓ File locking enabled"

echo ""
echo "========================================="
echo "Optimization Complete!"
echo "========================================="
echo ""
echo "Applied optimizations:"
echo "  ✓ System kernel parameters"
echo "  ✓ Docker configuration"
echo "  ✓ Nextcloud caching (APCu + Redis)"
echo "  ✓ Background jobs (cron)"
echo "  ✓ File locking"
echo ""
echo "Recommended next steps:"
echo "  1. Monitor performance for 24 hours"
echo "  2. Check logs: docker logs nextcloud-aio-nextcloud"
echo "  3. Run background jobs: docker exec -u www-data nextcloud-aio-nextcloud php occ background:cron"
echo ""
