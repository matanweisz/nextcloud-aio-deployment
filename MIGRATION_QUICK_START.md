# NextCloud Migration Quick Start Guide

**Simple step-by-step instructions to migrate NextCloud from Synology NAS to Ubuntu VM**

---

## 📋 Overview

**What we're doing:**
- Moving NextCloud from NAS Docker to dedicated Ubuntu VM
- NAS becomes storage only (via NFS)
- All processing happens on VM

**Estimated time:** 3-6 hours
**Downtime:** ~1 hour during data transfer

---

## ⚙️ Prerequisites Checklist

Before you start, ensure you have:

- [ ] Ubuntu 24.04 VM created (16GB RAM, 12 vCPU, 64GB disk)
- [ ] SSH access to both NAS and VM
- [ ] NAS IP address: `________________`
- [ ] VM IP address: `________________`
- [ ] Full backup of current NextCloud on NAS
- [ ] Maintenance window scheduled

---

## 🚀 Migration Steps

### STEP 1: Prepare VM (30 minutes)
**Location: Ubuntu VM via SSH**

```bash
# 1.1 - Update system
sudo apt update && sudo apt upgrade -y

# 1.2 - Install required packages
sudo apt install -y curl nfs-common vim

# 1.3 - Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# 1.4 - Logout and login again for Docker group to take effect
exit
```

Log back in and verify:
```bash
docker --version
docker compose version
```

---

### STEP 2: Extract Secrets from NAS (10 minutes)
**Location: Synology NAS via SSH**

```bash
# 2.1 - SSH into NAS
ssh admin@<NAS-IP>

# 2.2 - Extract all secrets (save this output!)
sudo docker inspect nextcloud-aio-nextcloud | grep -E "POSTGRES_PASSWORD|REDIS_HOST_PASSWORD|ADMIN_PASSWORD|AIO_TOKEN|TURN_SECRET|SIGNALING_SECRET|IMAGINARY_SECRET|WHITEBOARD_SECRET" > ~/nextcloud-secrets.txt

sudo docker inspect nextcloud-aio-talk | grep INTERNAL_SECRET >> ~/nextcloud-secrets.txt

# 2.3 - View and save the secrets
cat ~/nextcloud-secrets.txt
```

**📝 Copy these values** - you'll need them later!

Example output:
```
"POSTGRES_PASSWORD=1e0ca6b6b337e031b5be195000eac790d3931f0c59ffa190",
"REDIS_HOST_PASSWORD=a502d537791d19e15a3eba85b321e9eb22178af2c96db72b",
"ADMIN_PASSWORD=2c1e3d883cbdd5cea4cbbc569d698e3bf8889ff2c1db0af0",
...
```

---

### STEP 3: Create NAS Storage Share (15 minutes)
**Location: Synology NAS**

#### Option A: Via Synology DSM (Recommended)

1. Open DSM → **Control Panel** → **Shared Folder**
2. Click **Create**:
   - Name: `nextcloud-data`
   - Location: Choose volume with most space
3. Click **OK**

4. Go to **Control Panel** → **File Services** → **NFS** tab
5. Enable NFS service → **Apply**

6. Go back to **Shared Folder** → Select `nextcloud-data` → **Edit**
7. Click **NFS Permissions** → **Create**:
   - Server: `<VM-IP>`
   - Privilege: `Read/Write`
   - Squash: `No mapping`
   - Security: `sys`
   - ✅ Enable asynchronous
   - ✅ Allow non-privileged ports
   - ✅ Allow mounted subfolders
8. Click **Save**

#### Option B: Via SSH

```bash
# Still on NAS
sudo mkdir -p /volume1/nextcloud-data
sudo chown -R 33:33 /volume1/nextcloud-data
sudo chmod 750 /volume1/nextcloud-data

# Configure NFS export
echo "/volume1/nextcloud-data <VM-IP>(rw,async,no_wdelay,no_root_squash,insecure,anonuid=33,anongid=33)" | sudo tee -a /etc/exports

sudo exportfs -ra
```

---

### STEP 4: Test NFS Mount (5 minutes)
**Location: Ubuntu VM**

```bash
# 4.1 - Create mount point
sudo mkdir -p /mnt/nas-nextcloud-data

# 4.2 - Test mount (replace <NAS-IP>)
sudo mount -t nfs <NAS-IP>:/volume1/nextcloud-data /mnt/nas-nextcloud-data

# 4.3 - Verify mount
df -h | grep nextcloud

# 4.4 - Test write permissions
sudo touch /mnt/nas-nextcloud-data/test-file
ls -la /mnt/nas-nextcloud-data/
sudo rm /mnt/nas-nextcloud-data/test-file

# 4.5 - Unmount for now
sudo umount /mnt/nas-nextcloud-data
```

✅ **If this works, continue. If not, check NFS permissions on NAS.**

---

### STEP 5: Enable Maintenance Mode on NAS (2 minutes)
**Location: Synology NAS**

```bash
# SSH into NAS
ssh admin@<NAS-IP>

# Enable maintenance mode
sudo docker exec -u www-data nextcloud-aio-nextcloud php occ maintenance:mode --on

# Verify
sudo docker exec -u www-data nextcloud-aio-nextcloud php occ status
```

Users will now see "System in maintenance mode" when accessing NextCloud.

---

### STEP 6: Backup and Stop NAS Containers (30-60 minutes)
**Location: Synology NAS**

```bash
# 6.1 - Create backup directory
sudo mkdir -p /volume1/backups/nextcloud-migration

# 6.2 - Stop containers
cd /volume1/docker  # Or wherever your compose file is
sudo docker compose -f nas-docker-compose.yaml down

# 6.3 - Backup database
sudo docker run --rm \
  -v nextcloud_aio_database:/source:ro \
  -v /volume1/backups/nextcloud-migration:/backup \
  alpine tar czf /backup/database.tar.gz -C /source .

# 6.4 - Backup NextCloud app files
sudo docker run --rm \
  -v nextcloud_aio_nextcloud:/source:ro \
  -v /volume1/backups/nextcloud-migration:/backup \
  alpine tar czf /backup/nextcloud-app.tar.gz -C /source .

# 6.5 - Backup Apache data
sudo docker run --rm \
  -v nextcloud_aio_apache:/source:ro \
  -v /volume1/backups/nextcloud-migration:/backup \
  alpine tar czf /backup/apache.tar.gz -C /source .

# 6.6 - Copy user data to NAS share
sudo rsync -avxHAX --progress \
  /var/lib/docker/volumes/nextcloud_aio_nextcloud_data/_data/ \
  /volume1/nextcloud-data/

# 6.7 - Verify backups
ls -lh /volume1/backups/nextcloud-migration/
du -sh /volume1/nextcloud-data/
```

⏰ **This is the main downtime period** - NextCloud is now offline.

---

### STEP 7: Setup VM Configuration Files (10 minutes)
**Location: Ubuntu VM**

```bash
# 7.1 - Create working directory
mkdir -p ~/nextcloud
cd ~/nextcloud

# 7.2 - Copy configuration files from your local machine
# (Transfer nextcloud-vm-docker-compose.yaml and .env.example to VM)
```

**On your local machine:**
```bash
scp nextcloud-vm-docker-compose.yaml <user>@<VM-IP>:~/nextcloud/docker-compose.yaml
scp .env.example <user>@<VM-IP>:~/nextcloud/.env
```

**Back on VM:**
```bash
# 7.3 - Edit .env file with secrets from STEP 2
cd ~/nextcloud
nano .env

# Paste the values you saved from STEP 2:
# POSTGRES_PASSWORD=...
# REDIS_PASSWORD=...
# ADMIN_PASSWORD=...
# AIO_TOKEN=...
# TURN_SECRET=...
# SIGNALING_SECRET=...
# IMAGINARY_SECRET=...
# WHITEBOARD_SECRET=...
# INTERNAL_SECRET=...

# Save and exit (Ctrl+X, Y, Enter)
```

---

### STEP 8: Transfer Backups to VM (Variable time)
**Location: Ubuntu VM**

```bash
# 8.1 - Mount NAS backup folder temporarily
sudo mkdir -p /mnt/nas-backup
sudo mount -t nfs <NAS-IP>:/volume1/backups/nextcloud-migration /mnt/nas-backup

# 8.2 - Copy backups to VM
cd ~/nextcloud
cp /mnt/nas-backup/database.tar.gz .
cp /mnt/nas-backup/nextcloud-app.tar.gz .
cp /mnt/nas-backup/apache.tar.gz .

# 8.3 - Unmount
sudo umount /mnt/nas-backup

# 8.4 - Verify files
ls -lh ~/nextcloud/*.tar.gz
```

---

### STEP 9: Create Docker Volumes and Import Data (20 minutes)
**Location: Ubuntu VM**

```bash
cd ~/nextcloud

# 9.1 - Create volumes
docker volume create nextcloud_aio_nextcloud
docker volume create nextcloud_aio_database
docker volume create nextcloud_aio_apache
docker volume create nextcloud_aio_database_dump
docker volume create nextcloud_aio_redis

# 9.2 - Import database
docker run --rm \
  -v nextcloud_aio_database:/target \
  -v ~/nextcloud:/backup \
  alpine sh -c "cd /target && tar xzf /backup/database.tar.gz"

# 9.3 - Import NextCloud app files
docker run --rm \
  -v nextcloud_aio_nextcloud:/target \
  -v ~/nextcloud:/backup \
  alpine sh -c "cd /target && tar xzf /backup/nextcloud-app.tar.gz"

# 9.4 - Import Apache data
docker run --rm \
  -v nextcloud_aio_apache:/target \
  -v ~/nextcloud:/backup \
  alpine sh -c "cd /target && tar xzf /backup/apache.tar.gz"

# 9.5 - Verify
docker volume ls | grep nextcloud
```

---

### STEP 10: Configure Permanent NFS Mount (5 minutes)
**Location: Ubuntu VM**

```bash
# 10.1 - Create mount point
sudo mkdir -p /mnt/nas-nextcloud-data

# 10.2 - Add to /etc/fstab for auto-mount (replace <NAS-IP>)
echo "<NAS-IP>:/volume1/nextcloud-data /mnt/nas-nextcloud-data nfs auto,nofail,noatime,nolock,intr,tcp,actimeo=1800 0 0" | sudo tee -a /etc/fstab

# 10.3 - Mount
sudo mount -a

# 10.4 - Verify NAS data is accessible
ls -la /mnt/nas-nextcloud-data
df -h | grep nextcloud
```

You should see your user data files in `/mnt/nas-nextcloud-data`.

---

### STEP 11: Start NextCloud on VM (10 minutes)
**Location: Ubuntu VM**

```bash
cd ~/nextcloud

# 11.1 - Start all containers
docker compose up -d

# 11.2 - Watch startup (wait for all containers to be healthy)
docker compose logs -f

# Press Ctrl+C to exit logs

# 11.3 - Check status (wait until all show "Up" or "healthy")
watch -n 2 docker compose ps

# All containers should show "Up (healthy)" or just "Up"
# This may take 2-5 minutes
```

---

### STEP 12: Disable Maintenance Mode (2 minutes)
**Location: Ubuntu VM**

```bash
# 12.1 - Wait for NextCloud to be fully ready
sleep 30

# 12.2 - Disable maintenance mode
docker exec -u www-data nextcloud-aio-nextcloud php occ maintenance:mode --off

# 12.3 - Verify status
docker exec -u www-data nextcloud-aio-nextcloud php occ status
```

Expected output:
```
  - installed: true
  - version: 30.0.6
  - maintenance: false
```

---

### STEP 13: Verify Everything Works (15 minutes)
**Location: Ubuntu VM**

```bash
# 13.1 - Test HTTP access locally
curl -I http://localhost:11000

# 13.2 - Check all services
docker compose ps

# 13.3 - Verify database
docker exec -u www-data nextcloud-aio-nextcloud php occ db:status

# 13.4 - Scan files (verify NAS storage access)
docker exec -u www-data nextcloud-aio-nextcloud php occ files:scan --all

# 13.5 - Check for errors
docker compose logs | grep -i error | tail -50
```

**Test from another computer:**

```bash
# Add to /etc/hosts temporarily (on your test computer, not VM)
echo "<VM-IP> nextcloud.infinitylabs.co.il" | sudo tee -a /etc/hosts

# Open browser and test
# http://nextcloud.infinitylabs.co.il:11000
```

Login and verify:
- ✅ Can log in with admin account
- ✅ See all files
- ✅ Can upload a test file
- ✅ Can download a file
- ✅ Can edit a document (Collabora)

---

### STEP 14: Update Nginx Reverse Proxy (10 minutes)
**Location: Your Nginx Reverse Proxy Server**

Update your Nginx configuration to point to the new VM:

```nginx
upstream nextcloud-backend {
    server <VM-IP>:11000;  # Change from NAS IP to VM IP
}

server {
    listen 443 ssl http2;
    server_name nextcloud.infinitylabs.co.il;

    # Your existing SSL configuration
    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    # Important headers
    client_max_body_size 16G;
    client_body_timeout 300s;

    # Timeouts
    proxy_connect_timeout 300s;
    proxy_send_timeout 300s;
    proxy_read_timeout 300s;

    # Disable buffering for large uploads
    proxy_buffering off;
    proxy_request_buffering off;

    location / {
        proxy_pass http://nextcloud-backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Forwarded-Host $host;

        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
```

Test and reload:
```bash
sudo nginx -t
sudo systemctl reload nginx
```

---

### STEP 15: Update Firewall Rules (5 minutes)

**On your router/firewall:**

1. Update port forwarding for port 11000:
   - Change from: `NAS-IP:11000`
   - Change to: `VM-IP:11000`

2. Update Talk ports (3478 TCP/UDP):
   - Change from: `NAS-IP:3478`
   - Change to: `VM-IP:3478`

**On Ubuntu VM:**

```bash
# If using UFW firewall
sudo ufw allow 11000/tcp comment 'NextCloud'
sudo ufw allow 3478/tcp comment 'NextCloud Talk'
sudo ufw allow 3478/udp comment 'NextCloud Talk'
sudo ufw reload
```

---

### STEP 16: Go Live! (1 minute)
**Location: Your local computer**

```bash
# Remove the /etc/hosts entry you added in STEP 13
sudo sed -i '/<VM-IP> nextcloud.infinitylabs.co.il/d' /etc/hosts
```

**Test from browser:**
```
https://nextcloud.infinitylabs.co.il
```

✅ **You should now see NextCloud running from the VM!**

---

### STEP 17: Monitor (First 24 hours)
**Location: Ubuntu VM**

```bash
# Watch logs for errors
docker compose logs -f

# Monitor resource usage
htop

# Check container health
docker compose ps

# Check disk usage
df -h

# Monitor NFS mount
mount | grep nextcloud
```

---

### STEP 18: Setup Automated Backups (15 minutes)
**Location: Ubuntu VM**

```bash
# 18.1 - Create backup directory
sudo mkdir -p /opt/nextcloud-backup

# 18.2 - Create backup script
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

# 18.3 - Make executable
sudo chmod +x /opt/nextcloud-backup/backup-db.sh

# 18.4 - Test backup
sudo /opt/nextcloud-backup/backup-db.sh
ls -lh /var/backups/nextcloud/

# 18.5 - Schedule daily backups (2 AM)
echo "0 2 * * * root /opt/nextcloud-backup/backup-db.sh >> /var/log/nextcloud-backup.log 2>&1" | sudo tee /etc/cron.d/nextcloud-backup
```

---

## ✅ Post-Migration Checklist

Verify everything is working:

- [ ] Can access NextCloud via domain
- [ ] All users can log in
- [ ] All files visible and accessible
- [ ] File upload works
- [ ] File download works
- [ ] Collabora document editing works
- [ ] Talk video calls work
- [ ] Mobile apps connect successfully
- [ ] Desktop sync clients work
- [ ] No errors in logs
- [ ] Automated backups running

---

## 🔄 What to Do with NAS (After 30 Days)

**After confirming VM is stable for 30+ days:**

**Location: Synology NAS**

```bash
ssh admin@<NAS-IP>

# Remove old containers (volumes remain as backup)
cd /volume1/docker
sudo docker compose -f nas-docker-compose.yaml rm -f

# After 60 days, if everything is perfect, remove volumes
sudo docker volume ls | grep nextcloud
sudo docker volume rm nextcloud_aio_nextcloud
sudo docker volume rm nextcloud_aio_database
sudo docker volume rm nextcloud_aio_redis
sudo docker volume rm nextcloud_aio_apache
# Keep nextcloud_aio_nextcloud_data if you want extra backup

# Remove backup files
sudo rm -rf /volume1/backups/nextcloud-migration
```

**Keep NFS share active** - this is your production storage!

---

## 🆘 Quick Rollback (If Something Goes Wrong)

**If you need to rollback to NAS:**

**On Ubuntu VM:**
```bash
cd ~/nextcloud
docker compose down
```

**On Synology NAS:**
```bash
ssh admin@<NAS-IP>
cd /volume1/docker
sudo docker exec -u www-data nextcloud-aio-nextcloud php occ maintenance:mode --off
sudo docker compose -f nas-docker-compose.yaml up -d
```

**Update Nginx** to point back to NAS IP.

---

## 📊 Quick Troubleshooting

| Problem | Solution |
|---------|----------|
| Can't mount NFS | Check NFS service on NAS, verify IP in export config |
| Containers won't start | Check `.env` file has correct secrets, check logs with `docker compose logs` |
| "Trusted domain" error | `docker exec -u www-data nextcloud-aio-nextcloud php occ config:system:set trusted_domains 0 --value=nextcloud.infinitylabs.co.il` |
| Files not accessible | Verify NFS mount: `df -h \| grep nextcloud`, check permissions |
| Database connection error | Verify POSTGRES_PASSWORD matches in .env file |
| High CPU/RAM usage | Check `docker stats`, adjust resource limits in docker-compose.yaml |

---

## 📞 Need Help?

- **Check logs:** `docker compose logs -f [service-name]`
- **Check system status:** `docker exec -u www-data nextcloud-aio-nextcloud php occ status`
- **See detailed guide:** `NEXTCLOUD_MIGRATION_GUIDE.md`

---

## 🎯 Summary

**What you did:**
1. ✅ Set up Ubuntu VM with Docker
2. ✅ Extracted configuration from NAS
3. ✅ Created NFS share on NAS for storage
4. ✅ Migrated all data to VM and NAS storage
5. ✅ Started NextCloud on VM
6. ✅ Updated network configuration
7. ✅ Set up automated backups

**Result:**
- NextCloud runs on dedicated VM (faster, more resources)
- User data stored on NAS (reliable, large capacity)
- Separation of compute and storage (best practice)
- Easy to scale either component independently

**Congratulations! 🎉 Your migration is complete!**
