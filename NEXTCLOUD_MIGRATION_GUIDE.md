# NextCloud Migration Guide: Synology NAS to Ubuntu VM

## Table of Contents
1. [Overview](#overview)
2. [Prerequisites](#prerequisites)
3. [Pre-Migration Preparation](#pre-migration-preparation)
4. [Phase 1: VM Setup](#phase-1-vm-setup)
5. [Phase 2: Extract Configuration from NAS](#phase-2-extract-configuration-from-nas)
6. [Phase 3: Prepare NAS Storage](#phase-3-prepare-nas-storage)
7. [Phase 4: Data Migration](#phase-4-data-migration)
8. [Phase 5: Deploy on VM](#phase-5-deploy-on-vm)
9. [Phase 6: Verify and Switch Over](#phase-6-verify-and-switch-over)
10. [Phase 7: Cleanup](#phase-7-cleanup)
11. [Rollback Plan](#rollback-plan)
12. [Troubleshooting](#troubleshooting)

---

## Overview

This guide walks you through migrating your NextCloud All-in-One deployment from a Synology NAS Docker setup to a dedicated Ubuntu 24.04 VM, while using the NAS exclusively for storage.

**Migration Strategy:**
- Zero data loss approach with verification steps
- Minimal downtime (estimated 1-4 hours depending on data size)
- NAS becomes NFS/SMB storage backend only
- VM handles all NextCloud processing

**What will be migrated:**
- ✅ All user files and data
- ✅ Database (users, shares, metadata)
- ✅ All configurations and settings
- ✅ Installed apps and their data
- ✅ User accounts and permissions

---

## Prerequisites

### Required Access
- [ ] SSH access to Synology NAS
- [ ] Root/sudo access to Ubuntu VM
- [ ] Access to your network router/firewall configuration
- [ ] Access to external Nginx reverse proxy configuration

### Required Information
- [ ] NAS IP address: `___________________`
- [ ] VM IP address: `___________________`
- [ ] NextCloud domain: `nextcloud.infinitylabs.co.il`
- [ ] NAS admin credentials
- [ ] Sufficient storage on NAS (current usage + 20% buffer)

### System Requirements (VM)
- [x] Ubuntu 24.04 LTS installed
- [ ] 16 GB RAM
- [ ] 64 GB storage (OS + Docker volumes)
- [ ] 12 vCPUs
- [ ] Network connectivity to NAS
- [ ] Docker and Docker Compose installed

### Estimated Timing
| Phase | Duration | Downtime |
|-------|----------|----------|
| Preparation | 1-2 hours | No |
| VM Setup | 30 mins | No |
| Data Migration | Variable* | No |
| Deployment | 15 mins | No |
| Verification | 30 mins | No |
| Switchover | 5 mins | **YES** |

*Data migration time depends on data size and network speed

---

## Pre-Migration Preparation

### 1. Document Current State

**On your local machine, document the current setup:**

```bash
# Note current NAS IP
NAS_IP="10.6.0.21"  # Update with your actual IP

# Note current NextCloud URL
NEXTCLOUD_URL="https://nextcloud.infinitylabs.co.il"
```

### 2. Create Backup

**CRITICAL: Create a full backup before proceeding**

On Synology NAS:
1. Open Synology DSM
2. Go to **Hyper Backup**
3. Create a new backup task including:
   - Docker containers
   - Docker volumes
   - Docker configuration
4. Wait for backup to complete
5. Verify backup integrity

Alternatively, via CLI:

```bash
# SSH into Synology NAS
ssh admin@<NAS-IP>

# Stop NextCloud containers (schedule during maintenance window)
sudo docker compose -f /volume1/docker/nas-docker-compose.yaml down

# Create backup directory
sudo mkdir -p /volume1/backups/nextcloud-migration-$(date +%Y%m%d)

# Backup Docker volumes
sudo docker run --rm \
  -v nextcloud_aio_nextcloud:/source:ro \
  -v /volume1/backups/nextcloud-migration-$(date +%Y%m%d):/backup \
  alpine tar czf /backup/nextcloud-app.tar.gz -C /source .

sudo docker run --rm \
  -v nextcloud_aio_nextcloud_data:/source:ro \
  -v /volume1/backups/nextcloud-migration-$(date +%Y%m%d):/backup \
  alpine tar czf /backup/nextcloud-data.tar.gz -C /source .

sudo docker run --rm \
  -v nextcloud_aio_database:/source:ro \
  -v /volume1/backups/nextcloud-migration-$(date +%Y%m%d):/backup \
  alpine tar czf /backup/database.tar.gz -C /source .

# Restart containers
sudo docker compose -f /volume1/docker/nas-docker-compose.yaml up -d
```

### 3. Enable Maintenance Mode

**This prevents data changes during migration:**

```bash
# SSH into Synology NAS
ssh admin@<NAS-IP>

# Enable maintenance mode
sudo docker exec -u www-data nextcloud-aio-nextcloud php occ maintenance:mode --on

# Verify
sudo docker exec -u www-data nextcloud-aio-nextcloud php occ maintenance:mode
```

Users will see: "System is in maintenance mode"

---

## Phase 1: VM Setup

### 1. Install Ubuntu 24.04 on Hyper-V VM

**VM Configuration:**
- Name: `nextcloud-vm`
- Generation: 2
- Memory: 16384 MB (16 GB)
- Processors: 12 virtual cores
- Disk: 64 GB (dynamic)
- Network: Connected to same network as NAS

### 2. Initial Ubuntu Configuration

```bash
# SSH into Ubuntu VM
ssh <username>@<VM-IP>

# Update system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y \
  apt-transport-https \
  ca-certificates \
  curl \
  software-properties-common \
  nfs-common \
  cifs-utils \
  net-tools \
  htop \
  vim

# Set timezone (match NAS timezone)
sudo timedatectl set-timezone Asia/Jerusalem

# Set hostname
sudo hostnamectl set-hostname nextcloud-vm
```

### 3. Install Docker and Docker Compose

```bash
# Add Docker's official GPG key
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

# Add Docker repository
echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Install Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

# Start and enable Docker
sudo systemctl start docker
sudo systemctl enable docker

# Add your user to docker group
sudo usermod -aG docker $USER

# Log out and back in for group changes to take effect
exit
```

Log back in and verify:

```bash
ssh <username>@<VM-IP>
docker version
docker compose version
```

### 4. Configure System for NextCloud

```bash
# Increase file watchers (for NextCloud file monitoring)
echo "fs.inotify.max_user_watches=524288" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Increase open files limit
echo "fs.file-max = 2097152" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# Configure Docker logging
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  }
}
EOF

sudo systemctl restart docker
```

---

## Phase 2: Extract Configuration from NAS

### 1. Extract Environment Variables

**SSH into Synology NAS:**

```bash
ssh admin@<NAS-IP>

# Inspect the running NextCloud container to extract all secrets
sudo docker inspect nextcloud-aio-nextcloud | grep -E "POSTGRES_PASSWORD|REDIS_HOST_PASSWORD|ADMIN_PASSWORD|AIO_TOKEN|TURN_SECRET|SIGNALING_SECRET|IMAGINARY_SECRET|WHITEBOARD_SECRET|INTERNAL_SECRET"
```

**Save the output** - you'll need these values for the VM configuration.

Example output:
```
"POSTGRES_PASSWORD=1e0ca6b6b337e031b5be195000eac790d3931f0c59ffa190",
"REDIS_HOST_PASSWORD=a502d537791d19e15a3eba85b321e9eb22178af2c96db72b",
"ADMIN_PASSWORD=2c1e3d883cbdd5cea4cbbc569d698e3bf8889ff2c1db0af0",
"AIO_TOKEN=b2cfab2ea363ac1e7fa7099851bb1eaae58f567616806a28",
"TURN_SECRET=934d7dd7289c6278803f1792f7d80aad2698134398f2a8e3",
"SIGNALING_SECRET=6669df93c3e1baa2917c8119940a288f51f925b3d7127846",
"IMAGINARY_SECRET=73b12265b363563a62dc4dd210ca47b33eced4f20251e876",
"WHITEBOARD_SECRET=1affb90dd9b48f1718745e589a77b1f1f63494b6f8ce0b0b",
```

### 2. Extract INTERNAL_SECRET for Talk

```bash
# Inspect Talk container
sudo docker inspect nextcloud-aio-talk | grep INTERNAL_SECRET

# Example output:
# "INTERNAL_SECRET=85a7c920ed100e3b0dce1b283d2b7f927d0b239b418f8fa2",
```

### 3. Document Container Versions

```bash
# List all NextCloud AIO images and tags
sudo docker images | grep nextcloud/aio

# Save this information for reference
```

---

## Phase 3: Prepare NAS Storage

### 1. Create Shared Folder for NextCloud Data

**Option A: Using Synology DSM (Recommended)**

1. Open DSM Control Panel
2. Go to **Shared Folder**
3. Click **Create** → **Create Shared Folder**
4. Settings:
   - Name: `nextcloud-data`
   - Description: `NextCloud user data storage`
   - Location: Choose volume with most space
   - Enable Recycle Bin: ✅ (optional, for safety)
   - Enable data checksums: ✅ (if using Btrfs)

5. Click **Next** → **OK**

**Option B: Via CLI**

```bash
# SSH into NAS
ssh admin@<NAS-IP>

# Create shared folder
sudo mkdir -p /volume1/nextcloud-data
sudo chown -R 33:33 /volume1/nextcloud-data  # UID:GID for www-data
sudo chmod 750 /volume1/nextcloud-data
```

### 2. Configure NFS Export

**Via DSM:**

1. Control Panel → **File Services**
2. Go to **NFS** tab
3. Enable NFS service (if not already enabled)
4. Click **Apply**

5. Go to **Shared Folder**
6. Select `nextcloud-data`
7. Click **Edit** → **NFS Permissions**
8. Click **Create**:
   - Server or IP address: `<VM-IP>` (your Ubuntu VM IP)
   - Privilege: `Read/Write`
   - Squash: `No mapping`
   - Security: `sys`
   - Enable asynchronous: ✅
   - Allow connections from non-privileged ports: ✅
   - Allow users to access mounted subfolders: ✅

9. Click **Save**

**Via CLI (if needed):**

```bash
# Edit NFS exports
sudo vi /etc/exports

# Add this line (replace <VM-IP>):
/volume1/nextcloud-data <VM-IP>(rw,async,no_wdelay,no_root_squash,insecure,anonuid=33,anongid=33)

# Apply changes
sudo exportfs -ra

# Verify
sudo exportfs -v
```

### 3. Test NFS Mount from VM

**On Ubuntu VM:**

```bash
# Create mount point
sudo mkdir -p /mnt/nas-nextcloud-data

# Test mount
sudo mount -t nfs <NAS-IP>:/volume1/nextcloud-data /mnt/nas-nextcloud-data

# Verify
ls -la /mnt/nas-nextcloud-data
df -h | grep nextcloud

# Test write permissions
sudo -u www-data touch /mnt/nas-nextcloud-data/test-file
ls -la /mnt/nas-nextcloud-data/test-file
sudo rm /mnt/nas-nextcloud-data/test-file

# Unmount (we'll make it permanent later)
sudo umount /mnt/nas-nextcloud-data
```

If you encounter permission issues, verify UID/GID:

```bash
# Check www-data UID on VM
id -u www-data  # Should be 33

# On NAS, verify ownership
ssh admin@<NAS-IP>
ls -lan /volume1/nextcloud-data
```

---

## Phase 4: Data Migration

### 1. Stop NextCloud on NAS (Scheduled Downtime)

**Choose a maintenance window (e.g., overnight or weekend)**

```bash
# SSH into NAS
ssh admin@<NAS-IP>

# Enable maintenance mode
sudo docker exec -u www-data nextcloud-aio-nextcloud php occ maintenance:mode --on

# Stop all containers
cd /volume1/docker  # Or wherever your compose file is located
sudo docker compose -f nas-docker-compose.yaml down

# Verify all stopped
sudo docker ps | grep nextcloud
```

### 2. Copy Data to NAS Shared Folder

**Option A: Direct Copy (Fastest)**

```bash
# Still on NAS
# Copy user data
sudo rsync -avxHAX --progress \
  /var/lib/docker/volumes/nextcloud_aio_nextcloud_data/_data/ \
  /volume1/nextcloud-data/

# Verify copy
sudo du -sh /volume1/nextcloud-data
sudo ls -la /volume1/nextcloud-data
```

**Option B: Export and Import (Safer for corruption check)**

```bash
# Create temporary backup
sudo docker run --rm \
  -v nextcloud_aio_nextcloud_data:/source:ro \
  -v /volume1/backups:/backup \
  alpine tar czf /backup/nextcloud-data-migration.tar.gz -C /source .

# Extract to new location
sudo tar xzf /volume1/backups/nextcloud-data-migration.tar.gz -C /volume1/nextcloud-data/

# Set permissions
sudo chown -R 33:33 /volume1/nextcloud-data
```

### 3. Export Database

```bash
# On NAS - Create database dump
sudo docker run --rm \
  -v nextcloud_aio_database:/source:ro \
  -v /volume1/backups:/backup \
  alpine tar czf /backup/database-migration.tar.gz -C /source .

# Verify backup
ls -lh /volume1/backups/database-migration.tar.gz
```

### 4. Export Application Files

```bash
# On NAS - Export NextCloud installation
sudo docker run --rm \
  -v nextcloud_aio_nextcloud:/source:ro \
  -v /volume1/backups:/backup \
  alpine tar czf /backup/nextcloud-app-migration.tar.gz -C /source .

# Export Apache data
sudo docker run --rm \
  -v nextcloud_aio_apache:/source:ro \
  -v /volume1/backups:/backup \
  alpine tar czf /backup/apache-migration.tar.gz -C /source .

# List all backups
ls -lh /volume1/backups/*migration*
```

---

## Phase 5: Deploy on VM

### 1. Transfer Files to VM

**On Ubuntu VM:**

```bash
# Create working directory
mkdir -p ~/nextcloud-migration
cd ~/nextcloud-migration

# Mount NAS backup directory temporarily
sudo mkdir -p /mnt/nas-backup
sudo mount -t nfs <NAS-IP>:/volume1/backups /mnt/nas-backup

# Copy backup files to VM
sudo cp /mnt/nas-backup/database-migration.tar.gz ~/nextcloud-migration/
sudo cp /mnt/nas-backup/nextcloud-app-migration.tar.gz ~/nextcloud-migration/
sudo cp /mnt/nas-backup/apache-migration.tar.gz ~/nextcloud-migration/

# Set ownership
sudo chown $USER:$USER ~/nextcloud-migration/*.tar.gz

# Unmount
sudo umount /mnt/nas-backup
```

### 2. Copy Configuration Files to VM

**Transfer the new configuration files:**

```bash
# On your local machine (where you have the new config files)
scp nextcloud-vm-docker-compose.yaml <username>@<VM-IP>:~/nextcloud-migration/docker-compose.yaml
scp .env.example <username>@<VM-IP>:~/nextcloud-migration/.env
```

### 3. Configure Environment Variables

**On Ubuntu VM:**

```bash
cd ~/nextcloud-migration

# Edit .env file with the values extracted from NAS
vi .env
```

**Paste the values you extracted earlier:**

```env
POSTGRES_PASSWORD=1e0ca6b6b337e031b5be195000eac790d3931f0c59ffa190
REDIS_PASSWORD=a502d537791d19e15a3eba85b321e9eb22178af2c96db72b
ADMIN_PASSWORD=2c1e3d883cbdd5cea4cbbc569d698e3bf8889ff2c1db0af0
AIO_TOKEN=b2cfab2ea363ac1e7fa7099851bb1eaae58f567616806a28
TURN_SECRET=934d7dd7289c6278803f1792f7d80aad2698134398f2a8e3
SIGNALING_SECRET=6669df93c3e1baa2917c8119940a288f51f925b3d7127846
IMAGINARY_SECRET=73b12265b363563a62dc4dd210ca47b33eced4f20251e876
WHITEBOARD_SECRET=1affb90dd9b48f1718745e589a77b1f1f63494b6f8ce0b0b
INTERNAL_SECRET=85a7c920ed100e3b0dce1b283d2b7f927d0b239b418f8fa2
```

**CRITICAL: These MUST be the exact values from your NAS deployment!**

Save and exit.

### 4. Create Docker Volumes and Import Data

```bash
cd ~/nextcloud-migration

# Create named volumes
docker volume create nextcloud_aio_nextcloud
docker volume create nextcloud_aio_database
docker volume create nextcloud_aio_apache
docker volume create nextcloud_aio_database_dump
docker volume create nextcloud_aio_redis

# Import database
docker run --rm \
  -v nextcloud_aio_database:/target \
  -v ~/nextcloud-migration:/backup \
  alpine sh -c "cd /target && tar xzf /backup/database-migration.tar.gz"

# Import NextCloud application files
docker run --rm \
  -v nextcloud_aio_nextcloud:/target \
  -v ~/nextcloud-migration:/backup \
  alpine sh -c "cd /target && tar xzf /backup/nextcloud-app-migration.tar.gz"

# Import Apache data
docker run --rm \
  -v nextcloud_aio_apache:/target \
  -v ~/nextcloud-migration:/backup \
  alpine sh -c "cd /target && tar xzf /backup/apache-migration.tar.gz"

# Verify volumes
docker volume ls | grep nextcloud
```

### 5. Configure Permanent NFS Mount

```bash
# Create mount point
sudo mkdir -p /mnt/nas-nextcloud-data

# Add to /etc/fstab for automatic mounting
echo "<NAS-IP>:/volume1/nextcloud-data /mnt/nas-nextcloud-data nfs auto,nofail,noatime,nolock,intr,tcp,actimeo=1800 0 0" | sudo tee -a /etc/fstab

# Mount all (tests fstab entry)
sudo mount -a

# Verify
df -h | grep nextcloud
ls -la /mnt/nas-nextcloud-data

# Create .mount systemd unit for more reliable mounting (alternative/additional to fstab)
sudo tee /etc/systemd/system/mnt-nas-nextcloud-data.mount > /dev/null <<EOF
[Unit]
Description=NextCloud NFS Mount
After=network-online.target
Wants=network-online.target

[Mount]
What=<NAS-IP>:/volume1/nextcloud-data
Where=/mnt/nas-nextcloud-data
Type=nfs
Options=auto,nofail,noatime,nolock,intr,tcp,actimeo=1800

[Install]
WantedBy=multi-user.target
EOF

# Enable and start
sudo systemctl daemon-reload
sudo systemctl enable mnt-nas-nextcloud-data.mount
sudo systemctl start mnt-nas-nextcloud-data.mount

# Check status
sudo systemctl status mnt-nas-nextcloud-data.mount
```

### 6. Start NextCloud Containers

```bash
cd ~/nextcloud-migration

# Start all services
docker compose up -d

# Monitor startup
docker compose logs -f

# Wait for all containers to be healthy (may take 2-5 minutes)
watch -n 2 docker compose ps
```

**Expected output when ready:**
```
NAME                          STATUS
nextcloud-aio-apache          Up (healthy)
nextcloud-aio-collabora       Up (healthy)
nextcloud-aio-database        Up (healthy)
nextcloud-aio-imaginary       Up (healthy)
nextcloud-aio-nextcloud       Up (healthy)
nextcloud-aio-notify-push     Up (healthy)
nextcloud-aio-redis           Up (healthy)
nextcloud-aio-talk            Up (healthy)
nextcloud-aio-whiteboard      Up (healthy)
```

### 7. Disable Maintenance Mode

```bash
# Wait for NextCloud to fully start, then disable maintenance mode
docker exec -u www-data nextcloud-aio-nextcloud php occ maintenance:mode --off

# Verify
docker exec -u www-data nextcloud-aio-nextcloud php occ status
```

---

## Phase 6: Verify and Switch Over

### 1. Local Testing (Before DNS/Proxy Change)

**Test from VM itself:**

```bash
# Test local Apache connectivity
curl -I http://localhost:11000

# Expected: HTTP/1.1 302 Found (redirect to https)

# Test with host header
curl -H "Host: nextcloud.infinitylabs.co.il" http://localhost:11000
```

**Test from another machine on your network:**

```bash
# Add VM IP to /etc/hosts temporarily (on your test machine)
echo "<VM-IP> nextcloud.infinitylabs.co.il" | sudo tee -a /etc/hosts

# Test in browser
# Navigate to: http://nextcloud.infinitylabs.co.il:11000
```

### 2. Verification Checklist

**On the VM, verify functionality:**

```bash
# Check all containers running
docker compose ps

# Check NextCloud status
docker exec -u www-data nextcloud-aio-nextcloud php occ status

# Verify database connectivity
docker exec -u www-data nextcloud-aio-nextcloud php occ db:status

# Check file access (test with NAS storage)
docker exec -u www-data nextcloud-aio-nextcloud php occ files:scan --all

# Verify apps
docker exec -u www-data nextcloud-aio-nextcloud php occ app:list

# Check for errors
docker compose logs | grep -i error
docker compose logs nextcloud-aio-nextcloud | grep -i error
```

**Test via web interface (using temp /etc/hosts):**

1. Log in with admin credentials
2. Verify user accounts exist
3. Navigate to files - confirm you see your data
4. Test file upload/download
5. Test Collabora (edit a document)
6. Test Talk (start a call)
7. Check Settings → Administration → Overview for any warnings

### 3. Configure External Nginx Reverse Proxy

**On your Nginx reverse proxy server:**

```nginx
# Example Nginx configuration
# Add to your existing server block for nextcloud.infinitylabs.co.il

upstream nextcloud-vm {
    server <VM-IP>:11000;
}

server {
    listen 443 ssl http2;
    server_name nextcloud.infinitylabs.co.il;

    # SSL configuration (your existing SSL cert configuration)
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    # Security headers
    add_header Strict-Transport-Security "max-age=15768000; includeSubDomains; preload;" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Download-Options "noopen" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Permitted-Cross-Domain-Policies "none" always;
    add_header X-Robots-Tag "noindex, nofollow" always;
    add_header X-XSS-Protection "1; mode=block" always;

    # Remove X-Powered-By
    fastcgi_hide_header X-Powered-By;

    # Client body size (match NextCloud upload limit)
    client_max_body_size 16G;
    client_body_timeout 300s;
    client_body_buffer_size 512k;

    # Timeouts
    proxy_connect_timeout 300s;
    proxy_send_timeout 300s;
    proxy_read_timeout 300s;
    send_timeout 300s;

    # Buffering
    proxy_buffering off;
    proxy_request_buffering off;

    location / {
        proxy_pass http://nextcloud-vm;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;
        proxy_set_header X-Forwarded-Port $server_port;

        # WebSocket support for notify-push and Talk
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }

    # Notify push endpoint
    location ^~ /push/ {
        proxy_pass http://nextcloud-vm/push/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}

# HTTP redirect
server {
    listen 80;
    server_name nextcloud.infinitylabs.co.il;
    return 301 https://$server_name$request_uri;
}
```

**Test and reload Nginx:**

```bash
# Test configuration
sudo nginx -t

# If OK, reload
sudo systemctl reload nginx
```

### 4. Update Firewall Rules

**On your firewall/router:**

1. **Update port forwarding:**
   - Change port 11000 forwarding from NAS IP to VM IP

2. **Update Talk ports (3478 TCP/UDP):**
   - Change from NAS IP to VM IP

**On the VM:**

```bash
# If using UFW firewall
sudo ufw allow 11000/tcp comment 'NextCloud Apache'
sudo ufw allow 3478/tcp comment 'NextCloud Talk'
sudo ufw allow 3478/udp comment 'NextCloud Talk'

# Reload
sudo ufw reload
sudo ufw status
```

### 5. Switch Over (The Big Moment!)

**Before switching:**
- Ensure all verification tests passed
- Ensure Nginx proxy is configured
- Ensure firewall rules updated
- Have rollback plan ready

**The switch:**

1. **Update Nginx upstream** (if using temporary backend):
   - Remove NAS backend
   - Point to VM backend
   - `sudo nginx -t && sudo systemctl reload nginx`

2. **Remove /etc/hosts entry** from test machine

3. **Test from external network:**
   - Navigate to https://nextcloud.infinitylabs.co.il
   - Log in
   - Verify functionality

### 6. Monitor Initial Traffic

```bash
# On VM - monitor in real-time
docker compose logs -f

# Watch resource usage
htop

# Monitor NFS traffic
watch -n 2 'df -h | grep nextcloud'

# Check for errors
docker compose logs | grep -i error
```

### 7. Inform Users

**Send notification:**
- Migration completed successfully
- Service should work normally
- Report any issues immediately
- Note any performance improvements

---

## Phase 7: Cleanup

### 1. Keep NAS Containers Stopped

**On NAS - after confirming VM is stable for 24-48 hours:**

```bash
ssh admin@<NAS-IP>

# Verify containers are stopped
sudo docker ps -a | grep nextcloud

# Optional: Remove containers (but keep volumes for safety)
cd /volume1/docker
sudo docker compose -f nas-docker-compose.yaml rm -f

# DO NOT remove volumes yet - keep as backup for at least 1 month
```

### 2. Archive Migration Files

**On VM:**

```bash
# Move migration files to archive
sudo mkdir -p /var/backups/nextcloud-migration
sudo mv ~/nextcloud-migration/*.tar.gz /var/backups/nextcloud-migration/
sudo chmod 600 /var/backups/nextcloud-migration/*

# Keep for 30-60 days, then delete
```

### 3. Setup Automated Backups on VM

**Database backup script:**

```bash
# Create backup script
sudo mkdir -p /opt/nextcloud-backup
sudo tee /opt/nextcloud-backup/backup-db.sh > /dev/null <<'EOF'
#!/bin/bash
BACKUP_DIR="/var/backups/nextcloud"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Backup database
docker exec nextcloud-aio-database pg_dump -U nextcloud nextcloud_database | gzip > $BACKUP_DIR/db_$TIMESTAMP.sql.gz

# Keep only last 7 days
find $BACKUP_DIR -name "db_*.sql.gz" -mtime +7 -delete

echo "Backup completed: $TIMESTAMP"
EOF

sudo chmod +x /opt/nextcloud-backup/backup-db.sh

# Create cron job (daily at 2 AM)
echo "0 2 * * * root /opt/nextcloud-backup/backup-db.sh >> /var/log/nextcloud-backup.log 2>&1" | sudo tee /etc/cron.d/nextcloud-backup
```

**Test backup script:**

```bash
sudo /opt/nextcloud-backup/backup-db.sh
ls -lh /var/backups/nextcloud/
```

### 4. Remove Old NAS Volumes (After 30+ Days)

**Only after confirming everything works perfectly:**

```bash
# SSH into NAS
ssh admin@<NAS-IP>

# List volumes
sudo docker volume ls | grep nextcloud

# Remove (WARNING: PERMANENT!)
sudo docker volume rm nextcloud_aio_nextcloud
sudo docker volume rm nextcloud_aio_nextcloud_data  # User data is now on /volume1/nextcloud-data
sudo docker volume rm nextcloud_aio_database
sudo docker volume rm nextcloud_aio_redis
sudo docker volume rm nextcloud_aio_apache
sudo docker volume rm nextcloud_aio_database_dump

# Remove backup files (after successful migration + 60 days)
sudo rm -rf /volume1/backups/nextcloud-migration-*
```

---

## Rollback Plan

### If Migration Fails During Deployment

**Scenario: New VM deployment doesn't work**

1. **Keep NAS containers stopped**
2. **On NAS:**

```bash
ssh admin@<NAS-IP>

# Disable maintenance mode
sudo docker exec -u www-data nextcloud-aio-nextcloud php occ maintenance:mode --off

# Restart containers
cd /volume1/docker
sudo docker compose -f nas-docker-compose.yaml up -d

# Verify
sudo docker ps | grep nextcloud
```

3. **Revert Nginx configuration** to point back to NAS
4. **Revert firewall rules**
5. **Test access**

### If Issues Discovered After Switch

**Scenario: Users report problems after switching to VM**

1. **Assess severity:**
   - Critical (data loss, cannot access): Immediate rollback
   - Non-critical (performance, minor bugs): Fix forward

2. **For critical issues - immediate rollback:**

```bash
# On VM - stop containers
cd ~/nextcloud-migration
docker compose down

# On NAS - restart
ssh admin@<NAS-IP>
cd /volume1/docker
sudo docker exec -u www-data nextcloud-aio-nextcloud php occ maintenance:mode --off
sudo docker compose -f nas-docker-compose.yaml up -d
```

3. **Revert network configuration:**
   - Update Nginx to point to NAS
   - Update firewall rules
   - Test access

4. **Investigate and retry migration**

### Maximum Rollback Window

- **Full rollback possible:** First 30 days (while NAS volumes intact)
- **Partial rollback:** After 30 days (need to restore from backups)
- **Point of no return:** After removing NAS Docker volumes

---

## Troubleshooting

### Issue: NFS Mount Permission Denied

**Symptoms:**
- Cannot mount NFS share
- "Permission denied" errors

**Solution:**

```bash
# On NAS - verify export
ssh admin@<NAS-IP>
sudo exportfs -v | grep nextcloud-data

# Check NFS service
sudo systemctl status nfs-server

# On VM - check NFS client
sudo systemctl status nfs-client.target
sudo showmount -e <NAS-IP>

# Verify network connectivity
ping <NAS-IP>
telnet <NAS-IP> 2049
```

### Issue: Containers Fail to Start

**Symptoms:**
- Containers exit immediately
- "Unhealthy" status

**Solution:**

```bash
# Check logs
docker compose logs [service-name]

# Common issues:
# 1. Wrong secrets in .env
docker exec nextcloud-aio-nextcloud env | grep PASSWORD

# 2. Volume data corruption
docker compose down
docker volume rm nextcloud_aio_[volume]
# Re-import from backup

# 3. Port conflicts
sudo netstat -tulpn | grep 11000
```

### Issue: "Trusted Domain" Error

**Symptoms:**
- "Access through untrusted domain" message

**Solution:**

```bash
# Add trusted domain
docker exec -u www-data nextcloud-aio-nextcloud php occ config:system:set trusted_domains 0 --value=nextcloud.infinitylabs.co.il

# Verify
docker exec -u www-data nextcloud-aio-nextcloud php occ config:system:get trusted_domains
```

### Issue: Database Connection Failed

**Symptoms:**
- "Could not connect to database"
- 500 errors

**Solution:**

```bash
# Check database is running
docker compose ps nextcloud-aio-database

# Check password matches
docker exec nextcloud-aio-nextcloud env | grep POSTGRES_PASSWORD
docker exec nextcloud-aio-database env | grep POSTGRES_PASSWORD

# Test connection
docker exec nextcloud-aio-database psql -U nextcloud -d nextcloud_database -c "SELECT 1;"
```

### Issue: Files Not Accessible (NAS Storage)

**Symptoms:**
- Users see files in list but cannot download
- "File not found" errors

**Solution:**

```bash
# Verify NFS mount
df -h | grep nextcloud
ls -la /mnt/nas-nextcloud-data

# Check permissions
docker exec nextcloud-aio-nextcloud ls -la /mnt/ncdata

# Rescan files
docker exec -u www-data nextcloud-aio-nextcloud php occ files:scan --all

# Check for path issues in database
docker exec nextcloud-aio-database psql -U nextcloud -d nextcloud_database -c "SELECT * FROM oc_storages LIMIT 5;"
```

### Issue: High Resource Usage

**Symptoms:**
- VM sluggish
- OOM (Out of Memory) errors

**Solution:**

```bash
# Check resource usage
docker stats

# Identify culprit
htop

# Adjust resource limits in docker-compose.yaml
# Restart specific service
docker compose restart [service-name]

# Check for runaway processes
docker exec nextcloud-aio-nextcloud ps aux

# Review logs for errors causing loops
docker compose logs nextcloud-aio-nextcloud | grep -i error
```

### Issue: Collabora Not Working

**Symptoms:**
- Documents won't open
- "Failed to load Collabora" error

**Solution:**

```bash
# Check Collabora container
docker compose logs nextcloud-aio-collabora

# Verify connectivity
docker exec nextcloud-aio-nextcloud wget -O- http://nextcloud-aio-collabora:9980

# Reactivate Collabora config
docker exec -u www-data nextcloud-aio-nextcloud php occ richdocuments:activate-config

# Check settings
docker exec -u www-data nextcloud-aio-nextcloud php occ config:app:get richdocuments wopi_url
```

### Issue: Talk Not Working

**Symptoms:**
- Cannot make calls
- TURN server unreachable

**Solution:**

```bash
# Verify ports are open
sudo netstat -tulpn | grep 3478

# Check firewall
sudo ufw status | grep 3478

# Test from external network
nc -zv <VM-PUBLIC-IP> 3478

# Verify Talk secrets match
docker exec nextcloud-aio-nextcloud env | grep TURN_SECRET
docker exec nextcloud-aio-talk env | grep TURN_SECRET

# Check Talk settings in NextCloud
docker exec -u www-data nextcloud-aio-nextcloud php occ talk:turn:list
```

### Getting Help

If you encounter issues not covered here:

1. **Check logs:**
   ```bash
   docker compose logs -f
   ```

2. **NextCloud system info:**
   ```bash
   docker exec -u www-data nextcloud-aio-nextcloud php occ status
   docker exec -u www-data nextcloud-aio-nextcloud php occ check
   ```

3. **Search NextCloud Community:**
   - https://help.nextcloud.com/

4. **Check GitHub Issues:**
   - https://github.com/nextcloud/all-in-one/issues

---

## Post-Migration Optimization

### 1. Enable Cron Jobs

```bash
# Set background job mode to cron
docker exec -u www-data nextcloud-aio-nextcloud php occ background:cron

# Add to host crontab
echo "*/5 * * * * docker exec -u www-data nextcloud-aio-nextcloud php -f /var/www/html/cron.php" | sudo tee -a /etc/cron.d/nextcloud
```

### 2. Enable Memory Caching

Already configured via Redis in docker-compose.yaml ✅

### 3. Configure Preview Generation

```bash
# Enable preview generation
docker exec -u www-data nextcloud-aio-nextcloud php occ config:system:set enable_previews --value=true --type=boolean

# Set max preview size
docker exec -u www-data nextcloud-aio-nextcloud php occ config:system:set preview_max_x --value=2048 --type=integer
docker exec -u www-data nextcloud-aio-nextcloud php occ config:system:set preview_max_y --value=2048 --type=integer

# Generate previews
docker exec -u www-data nextcloud-aio-nextcloud php occ preview:generate-all
```

### 4. Setup Monitoring

**Install monitoring tools:**

```bash
# Prometheus + Grafana (optional)
# Or use simple log monitoring:

# Install logwatch
sudo apt install logwatch

# Monitor Docker logs
sudo tee /etc/logwatch/conf/services/docker-nextcloud.conf > /dev/null <<EOF
Title = "NextCloud Docker"
LogFile = NONE
*Command = "/usr/bin/docker compose -f /home/$USER/nextcloud-migration/docker-compose.yaml logs --tail=100"
EOF
```

### 5. Setup Alerts

```bash
# Simple email alerts for container failures
sudo tee /opt/nextcloud-backup/check-health.sh > /dev/null <<'EOF'
#!/bin/bash
UNHEALTHY=$(docker compose -f /home/$(logname)/nextcloud-migration/docker-compose.yaml ps | grep -i unhealthy | wc -l)

if [ $UNHEALTHY -gt 0 ]; then
    echo "ALERT: $UNHEALTHY NextCloud containers are unhealthy!" | mail -s "NextCloud Alert" admin@infinitylabs.co.il
fi
EOF

sudo chmod +x /opt/nextcloud-backup/check-health.sh

# Run every 5 minutes
echo "*/5 * * * * root /opt/nextcloud-backup/check-health.sh" | sudo tee /etc/cron.d/nextcloud-health
```

---

## Success Criteria

✅ **Migration is successful when:**

- [ ] All users can log in
- [ ] All files are accessible
- [ ] File upload/download works
- [ ] All installed apps function correctly
- [ ] Collabora document editing works
- [ ] Talk video calls work
- [ ] No errors in logs
- [ ] Performance is acceptable or better than before
- [ ] Backups are running automatically
- [ ] Monitoring is in place
- [ ] NAS is functioning purely as storage (containers stopped)

---

## Summary Timeline

| Day | Action |
|-----|--------|
| **Day 0** | Preparation, backups, read guide completely |
| **Day 1** | VM setup, Docker installation, NFS configuration |
| **Day 2** | Extract configs, test NFS mount, prepare storage |
| **Day 3** | **MIGRATION DAY** - Data copy, deploy, verify |
| **Day 4-7** | Monitor closely, address any issues |
| **Day 30** | If stable, remove NAS containers (keep volumes) |
| **Day 60** | If stable, remove NAS volumes and backups |

---

## Final Checklist

**Before you start:**
- [ ] Read entire guide
- [ ] Understand each step
- [ ] Have rollback plan ready
- [ ] Schedule maintenance window
- [ ] Notify users of planned maintenance
- [ ] Verify all prerequisites met
- [ ] Have backups confirmed

**After migration:**
- [ ] All services accessible
- [ ] Data integrity verified
- [ ] Performance acceptable
- [ ] Monitoring configured
- [ ] Backups scheduled
- [ ] Documentation updated
- [ ] Users notified of completion

---

**Good luck with your migration! Take your time and don't skip verification steps.** 🚀
