# Nextcloud AIO Migration - Step-by-Step Guide

> **Follow these 33 steps on migration day. Check off each step as completed.**

**Estimated Time:** 6-7 hours | **Downtime:** 1-2 hours (Steps 5-7 only)

---

## Before You Start

✅ **Completed `PRE_MIGRATION_VALIDATION.md`? (95%+ pass rate required)**
✅ **Have `QUICK_REFERENCE.md` open?** (for commands)
✅ **Maintenance window active?** (users notified)
✅ **Backup verified?** (tested restore)

---

# Phase 1: Extract Data from NAS (2 hours)

## Step 1: Extract config.php Values ⏱️ 10 min

**On NAS:**
```bash
ssh admin@<NAS-IP>

# Extract critical values
sudo docker exec nextcloud-aio-nextcloud cat /var/www/html/config/config.php > ~/nextcloud-config.php

# Extract the three critical values
sudo docker exec nextcloud-aio-nextcloud grep -E "instanceid|passwordsalt|secret" /var/www/html/config/config.php > ~/migration-secrets.txt

# View and save
cat ~/migration-secrets.txt
```

**✅ Verify:** All three values present (instanceid, passwordsalt, secret)

- [ ] **Step 1 complete**

---

## Step 2: Create Database Dump ⏱️ 15 min

**On NAS:**
```bash
# Create backup directory
sudo mkdir -p /volume1/nextcloud-migration

# Dump database
sudo docker exec nextcloud-aio-database pg_dump -U nextcloud nextcloud_database > /volume1/nextcloud-migration/database-dump.sql

# Verify
ls -lh /volume1/nextcloud-migration/database-dump.sql
# Should be > 1MB

# Check content
head -50 /volume1/nextcloud-migration/database-dump.sql
# Should show PostgreSQL dump header
```

**✅ Verify:** Dump file exists and contains data

- [ ] **Step 2 complete**

---

## Step 3: Create NFS Share for Data ⏱️ 10 min

**On NAS via DSM Web Interface:**
1. Control Panel → Shared Folder → Create
2. Name: `nextcloud-vm-data`
3. Control Panel → File Services → NFS → Enable
4. Shared Folder → nextcloud-vm-data → NFS Permissions → Create:
   - Server: `<VM-IP>`
   - Privilege: Read/Write
   - Squash: No mapping
   - ✅ Enable asynchronous
   - ✅ Allow non-privileged ports

**✅ Verify:** NFS export created

- [ ] **Step 3 complete**

---

## Step 4: Copy User Data to NFS Share ⏱️ 30-60 min

**On NAS:**
```bash
# Find current data location
sudo docker exec -u www-data nextcloud-aio-nextcloud php occ config:system:get datadirectory

# Copy data (adjust path if needed)
sudo rsync -avxHAX --progress \
  /var/lib/docker/volumes/nextcloud_aio_nextcloud_data/_data/ \
  /volume1/nextcloud-vm-data/

# Verify size matches
du -sh /var/lib/docker/volumes/nextcloud_aio_nextcloud_data/_data
du -sh /volume1/nextcloud-vm-data
```

**✅ Verify:** Sizes match, no errors

- [ ] **Step 4 complete**

---

## Step 5: Enable Maintenance Mode ⏱️ 2 min

**On NAS:**
```bash
sudo docker exec -u www-data nextcloud-aio-nextcloud php occ maintenance:mode --on

# Verify
sudo docker exec -u www-data nextcloud-aio-nextcloud php occ status
# Should show: maintenance: true
```

**⚠️ DOWNTIME BEGINS** - Users see maintenance page

**✅ Verify:** Maintenance mode enabled

- [ ] **Step 5 complete**

---

## Step 6: Set NFS Permissions ⏱️ 5 min

**On NAS:**
```bash
# Set correct ownership (www-data = UID 33)
sudo chown -R 33:33 /volume1/nextcloud-vm-data/
sudo chmod -R 750 /volume1/nextcloud-vm-data/

# Verify
ls -lan /volume1/nextcloud-vm-data/ | head -5
# Should show UID 33
```

**✅ Verify:** Ownership is 33:33

- [ ] **Step 6 complete**

---

## Step 7: Transfer Migration Files ⏱️ 5 min

**On NAS:**
```bash
# Copy migration files to accessible location
sudo cp ~/migration-secrets.txt /volume1/nextcloud-migration/
sudo cp ~/nextcloud-config.php /volume1/nextcloud-migration/

# Create archive
cd /volume1/nextcloud-migration
sudo tar czf migration-files.tar.gz database-dump.sql migration-secrets.txt nextcloud-config.php

# Verify
ls -lh migration-files.tar.gz
```

**✅ Verify:** Archive created

- [ ] **Step 7 complete**

---

# Phase 2: Prepare Ubuntu VM (1 hour)

## Step 8: Install Docker ⏱️ 15 min

**On Ubuntu VM:**
```bash
ssh <user>@<VM-IP>

# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Add user to docker group
sudo usermod -aG docker $USER

# MUST logout and login again
exit
```

**Re-login and verify:**
```bash
ssh <user>@<VM-IP>
docker --version
# Should work without sudo
```

**✅ Verify:** Docker installed, works without sudo

- [ ] **Step 8 complete**

---

## Step 9: Install and Configure NFS ⏱️ 10 min

**On Ubuntu VM:**
```bash
# Install NFS client
sudo apt install -y nfs-common

# Test NFS connectivity
showmount -e <NAS-IP>
# Should list: /volume1/nextcloud-vm-data

# Create mount point
sudo mkdir -p /mnt/nas-nextcloud-data

# Test mount
sudo mount -t nfs <NAS-IP>:/volume1/nextcloud-vm-data /mnt/nas-nextcloud-data

# Verify
df -h | grep nextcloud
ls -la /mnt/nas-nextcloud-data/ | head -5

# Test write
sudo -u '#33' touch /mnt/nas-nextcloud-data/test-$(date +%s)

# Unmount for now
sudo umount /mnt/nas-nextcloud-data
```

**✅ Verify:** NFS mount works, can write

- [ ] **Step 9 complete**

---

## Step 10: Configure Permanent NFS Mount ⏱️ 5 min

**On Ubuntu VM:**
```bash
# Add to /etc/fstab
echo "<NAS-IP>:/volume1/nextcloud-vm-data /mnt/nas-nextcloud-data nfs vers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,actimeo=1,nofail,_netdev,bg 0 0" | sudo tee -a /etc/fstab

# Mount all
sudo mount -a

# Verify permanent mount
df -h | grep nextcloud
mount | grep nextcloud
```

**✅ Verify:** NFS mounted, survives reboot

- [ ] **Step 10 complete**

---

## Step 11: Transfer Migration Files to VM ⏱️ 10 min

**From your workstation OR on VM:**
```bash
# Option 1: From workstation
scp admin@<NAS-IP>:/volume1/nextcloud-migration/migration-files.tar.gz .
scp migration-files.tar.gz <user>@<VM-IP>:~/

# Option 2: Direct from VM
ssh <user>@<VM-IP>
scp admin@<NAS-IP>:/volume1/nextcloud-migration/migration-files.tar.gz ~/

# Extract on VM
mkdir -p ~/nextcloud-migration
cd ~/nextcloud-migration
tar xzf ../migration-files.tar.gz

# Verify files
ls -lh
# Should see: database-dump.sql, migration-secrets.txt, nextcloud-config.php
```

**✅ Verify:** All files extracted on VM

- [ ] **Step 11 complete**

---

## Step 12: Modify Database Paths ⏱️ 10 min

**On Ubuntu VM:**
```bash
cd ~/nextcloud-migration

# Backup original
cp database-dump.sql database-dump.sql.backup

# Check current path in database
grep "local::/" database-dump.sql | head -3
# Note the current path

# IF path needs changing (e.g., not /mnt/ncdata):
# sed -i 's|local::/old/path/|local::/mnt/ncdata/|g' database-dump.sql

# Check database owner
grep "Owner:" database-dump.sql | head -3
# If shows "nextcloud", must change to "ncadmin"

# Change owner if needed
sed -i 's|Owner: nextcloud$|Owner: ncadmin|g' database-dump.sql
sed -i 's| OWNER TO nextcloud;$| OWNER TO ncadmin;|g' database-dump.sql

# Verify changes
grep "local::/" database-dump.sql | head -3
grep "Owner:" database-dump.sql | head -3
```

**✅ Verify:** Paths correct, owner is ncadmin

- [ ] **Step 12 complete**

---

## Step 13: Optimize VM System ⏱️ 5 min

**On Ubuntu VM:**
```bash
# System limits
sudo tee /etc/sysctl.d/99-nextcloud.conf <<EOF
fs.inotify.max_user_watches=524288
net.core.somaxconn=65535
vm.swappiness=10
EOF

sudo sysctl -p /etc/sysctl.d/99-nextcloud.conf

# Docker optimization
sudo tee /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2"
}
EOF

sudo systemctl restart docker
```

**✅ Verify:** No errors, docker restarted

- [ ] **Step 13 complete**

---

# Phase 3: Install Nextcloud AIO (30 min)

## Step 14: Create Docker Compose File ⏱️ 5 min

**On Ubuntu VM:**
```bash
mkdir -p ~/nextcloud
cd ~/nextcloud

# Copy the docker-compose-mastercontainer.yaml from this repo to ~/nextcloud/
# Or create it directly
```

**Use the `docker-compose-mastercontainer.yaml` from the repository.**

**✅ Verify:** Compose file exists in ~/nextcloud/

- [ ] **Step 14 complete**

---

## Step 15: Start Mastercontainer ⏱️ 10 min

**On Ubuntu VM:**
```bash
cd ~/nextcloud

# Start mastercontainer
docker compose -f docker-compose-mastercontainer.yaml up -d

# Check status
docker ps | grep mastercontainer
# Should show "Up"

# Get AIO password
docker logs nextcloud-aio-mastercontainer 2>&1 | grep "password"
# Save this password!
```

**✅ Verify:** Mastercontainer running, have password

- [ ] **Step 15 complete**

---

## Step 16: Configure AIO via Web Interface ⏱️ 15 min

**In browser: `https://<VM-IP>:8080`**

1. Accept self-signed certificate
2. Enter password from Step 15
3. Enter domain: `nextcloud.infinitylabs.co.il`
4. Click "Submit domain" (will fail - expected)
5. Check "Skip domain validation"
6. Click "Submit domain" again
7. Select containers:
   - ✅ Nextcloud Talk
   - ✅ Collabora
   - ✅ Imaginary
   - ✅ Whiteboard
   - ❌ ClamAV (disabled for performance)
8. Set timezone: `Asia/Jerusalem`
9. Click "Download and start containers"
10. Wait for all containers to download and start (10-15 min)

**✅ Verify:** All containers show "Running" in AIO interface

- [ ] **Step 16 complete**

---

## Step 17: Create Initial Backup ⏱️ 10 min

**In AIO interface:**
1. Go to "Backup and restore"
2. Click "Create backup"
3. Wait for completion

**✅ Verify:** Backup shows "Completed"

- [ ] **Step 17 complete**

---

# Phase 4: Migrate Data (1.5 hours)

## Step 18: Stop Containers for Import ⏱️ 2 min

**In AIO interface:**
1. Click "Stop containers"
2. Wait for all to stop

**On VM, verify:**
```bash
docker ps --filter name=nextcloud-aio
# Should only show mastercontainer
```

**✅ Verify:** Only mastercontainer running

- [ ] **Step 18 complete**

---

## Step 19: Import Database ⏱️ 15 min

**On Ubuntu VM:**
```bash
cd ~/nextcloud-migration

# Copy dump to database volume
docker cp database-dump.sql nextcloud-aio-database:/mnt/data/

# Set permissions
docker run --rm --volume nextcloud_aio_database_dump:/mnt/data:rw alpine chmod 777 /mnt/data/database-dump.sql

# Remove cleanup marker (triggers import on next start)
docker run --rm --volume nextcloud_aio_database_dump:/mnt/data:rw alpine rm -f /mnt/data/initial-cleanup-done

# Clear old database data
docker run --rm --volume nextcloud_aio_database:/var/lib/postgresql/data:rw alpine sh -c "rm -rf /var/lib/postgresql/data/*"

# Verify
docker run --rm --volume nextcloud_aio_database_dump:/mnt/data:ro alpine ls -lh /mnt/data/
# Should show database-dump.sql
```

**✅ Verify:** Database dump ready for import

- [ ] **Step 19 complete**

---

## Step 20: Migrate config.php Values ⏱️ 15 min

**On Ubuntu VM:**
```bash
cd ~/nextcloud-migration

# Extract values
INSTANCE_ID=$(grep "instanceid:" migration-secrets.txt | cut -d"'" -f2)
PASSWORD_SALT=$(grep "passwordsalt:" migration-secrets.txt | cut -d"'" -f2)
SECRET=$(grep "secret:" migration-secrets.txt | cut -d"'" -f2)

# Verify variables
echo "instanceid: $INSTANCE_ID"
echo "passwordsalt: $PASSWORD_SALT"
echo "secret: $SECRET"

# Edit config.php
docker run -it --rm --volume nextcloud_aio_nextcloud:/var/www/html:rw alpine sh -c "apk add --no-cache nano && nano /var/www/html/config/config.php"
```

**In nano editor, replace these three values:**
1. Find `'instanceid'` → Replace with value from $INSTANCE_ID
2. Find `'passwordsalt'` → Replace with value from $PASSWORD_SALT
3. Find `'secret'` → Replace with value from $SECRET

**Save:** Ctrl+O, Enter, Ctrl+X

**✅ Verify:** All three values updated

- [ ] **Step 20 complete**

---

## Step 21: Configure Trusted Proxy ⏱️ 5 min

**On Ubuntu VM:**
```bash
# Edit config.php again
docker run -it --rm --volume nextcloud_aio_nextcloud:/var/www/html:rw alpine sh -c "apk add --no-cache nano && nano /var/www/html/config/config.php"
```

**Add/verify these settings:**
```php
'trusted_proxies' =>
array (
  0 => '<NGINX-IP>',  // Your Nginx server IP
),

'overwriteprotocol' => 'https',
'overwritehost' => 'nextcloud.infinitylabs.co.il',
```

**Save:** Ctrl+O, Enter, Ctrl+X

**✅ Verify:** Proxy settings added

- [ ] **Step 21 complete**

---

# Phase 5: Start and Verify (1 hour)

## Step 22: Start All Containers ⏱️ 15 min

**In AIO interface:**
1. Click "Start containers"
2. Watch startup progress
3. Database will import (takes longest - watch logs)

**On VM, monitor database import:**
```bash
docker logs -f nextcloud-aio-database
# Watch for: "Database import completed"
# Press Ctrl+C when done
```

**Wait for all containers to show "Running" in AIO interface.**

**✅ Verify:** All containers running

- [ ] **Step 22 complete**

---

## Step 23: Scan Files ⏱️ 30 min

**On Ubuntu VM:**
```bash
# Scan all files
docker exec --user www-data nextcloud-aio-nextcloud php occ files:scan-app-data
docker exec --user www-data nextcloud-aio-nextcloud php occ files:scan --all

# This takes 10-30 minutes depending on file count
```

**✅ Verify:** Scan completes without errors

- [ ] **Step 23 complete**

---

## Step 24: Verify Nextcloud Status ⏱️ 5 min

**On Ubuntu VM:**
```bash
# Check status
docker exec --user www-data nextcloud-aio-nextcloud php occ status

# Expected output:
#   - installed: true
#   - maintenance: false
#   - needsDbUpgrade: false

# Check all containers
docker ps --filter name=nextcloud-aio --format "table {{.Names}}\t{{.Status}}"
# All should show "Up (healthy)" or "Up"
```

**✅ Verify:** Status looks good, maintenance: false

- [ ] **Step 24 complete**

---

## Step 25: Test Login Locally ⏱️ 10 min

**On your workstation:**
```bash
# Add hosts entry for testing
echo "<VM-IP> nextcloud.infinitylabs.co.il" | sudo tee -a /etc/hosts
```

**In browser: `http://nextcloud.infinitylabs.co.il:11000`**

**Test:**
1. ✅ Login page appears
2. ✅ Can login with admin account (**CRITICAL** - if this fails, config.php migration failed)
3. ✅ Files are visible
4. ✅ Can upload small file
5. ✅ Can download file

**If login fails:** Go back to Step 20, verify config.php values match exactly

**✅ Verify:** Login works, files accessible

- [ ] **Step 25 complete**

---

# Phase 6: Configure Nginx (30 min)

## Step 26: Update Nginx Configuration ⏱️ 15 min

**On Nginx server:**

See `config/nginx-config.conf` for complete configuration.

**Key changes:**
1. Update upstream: `server <VM-IP>:11000;`
2. Verify SSL certificates path
3. Ensure WebSocket support included

**Test and apply:**
```bash
sudo nginx -t
sudo systemctl reload nginx
```

**✅ Verify:** Nginx config valid, reloaded

- [ ] **Step 26 complete**

---

## Step 27: Configure Firewall ⏱️ 10 min

**On Ubuntu VM:**
```bash
# Configure UFW
sudo ufw allow ssh
sudo ufw allow from <NGINX-IP> to any port 11000 proto tcp comment 'Nextcloud'
sudo ufw allow 3478/tcp comment 'Talk TCP'
sudo ufw allow 3478/udp comment 'Talk UDP'
sudo ufw enable

# Verify
sudo ufw status numbered
```

**✅ Verify:** Firewall rules active

- [ ] **Step 27 complete**

---

## Step 28: Remove Test Hosts Entry ⏱️ 2 min

**On your workstation:**
```bash
# Remove test entry
sudo sed -i.bak '/<VM-IP> nextcloud.infinitylabs.co.il/d' /etc/hosts
```

**✅ Verify:** Hosts entry removed

- [ ] **Step 28 complete**

---

# Phase 7: Go Live (30 min)

## Step 29: Test via Domain ⏱️ 15 min

**In browser: `https://nextcloud.infinitylabs.co.il`**

**Complete testing:**
1. ✅ HTTPS works (green padlock)
2. ✅ Login works
3. ✅ All files visible
4. ✅ Upload 100MB+ file
5. ✅ Download file
6. ✅ Open office document (Collabora)
7. ✅ Share link works
8. ✅ Mobile app connects
9. ✅ No console errors (F12)

**✅ Verify:** Everything works via HTTPS domain

- [ ] **Step 29 complete**

---

## Step 30: Disable Maintenance on NAS ⏱️ 2 min

**On NAS:**
```bash
ssh admin@<NAS-IP>

# Disable maintenance (for cleanup access later)
sudo docker exec -u www-data nextcloud-aio-nextcloud php occ maintenance:mode --off
```

**DO NOT start NAS containers yet** - keep as backup for 30 days

**✅ Verify:** Maintenance mode off on NAS

- [ ] **Step 30 complete**

---

## Step 31: Configure AIO Backups ⏱️ 10 min

**In AIO interface:**
1. Go to "Backup and restore"
2. Set backup location: `/mnt/nas-nextcloud-data/aio-backups`
3. Schedule: Daily at 2 AM
4. Click "Save"
5. Test backup now

**✅ Verify:** Backup configured and tested

- [ ] **Step 31 complete**

---

## Step 32: Apply Performance Optimizations ⏱️ 5 min

**On Ubuntu VM:**
```bash
# Run optimization script
# See config/system-optimization.sh for details

# Or apply manually:
docker exec -u www-data nextcloud-aio-nextcloud php occ config:system:set memcache.local --value='\\OC\\Memcache\\APCu'
docker exec -u www-data nextcloud-aio-nextcloud php occ config:system:set memcache.distributed --value='\\OC\\Memcache\\Redis'
docker exec -u www-data nextcloud-aio-nextcloud php occ background:cron
```

**✅ Verify:** Optimizations applied

- [ ] **Step 32 complete**

---

## Step 33: Final Verification ⏱️ 10 min

**Complete final checklist:**

- [ ] ✅ Login works (config.php migration succeeded)
- [ ] ✅ All files accessible (database + NFS correct)
- [ ] ✅ Upload/download works
- [ ] ✅ Collabora works
- [ ] ✅ Mobile app syncs
- [ ] ✅ Desktop client syncs
- [ ] ✅ No errors in logs
- [ ] ✅ All containers healthy
- [ ] ✅ Performance acceptable (< 2 sec page loads)

**Check logs:**
```bash
docker logs nextcloud-aio-nextcloud --tail 50 | grep -i error
# Should show no critical errors
```

**✅ Verify:** All checks passed

- [ ] **Step 33 complete**

---

# 🎉 Migration Complete!

## ⏰ Downtime Summary
- **Total time:** ______ hours
- **Downtime:** ______ hours (Steps 5-7)
- **Issues encountered:** ______

## 📊 Post-Migration Tasks

### **Next 48 Hours:** Monitor Closely
```bash
# Check container health every 2 hours
docker ps --filter name=nextcloud-aio

# Monitor logs
docker logs -f nextcloud-aio-nextcloud

# Check resources
docker stats

# Verify NFS mount
mount | grep nextcloud
```

### **Week 1:** Standard Monitoring
- Check logs daily
- Monitor performance
- Collect user feedback
- Verify backups running

### **After 30 Days:** Cleanup NAS
If everything stable for 30+ days:
```bash
# On NAS - stop old containers
sudo docker stop $(sudo docker ps -a --filter name=nextcloud-aio --format "{{.Names}}")

# After 60 days - remove if confident
# sudo docker rm $(sudo docker ps -a --filter name=nextcloud-aio --format "{{.Names}}")
```

---

## 🆘 Emergency Rollback (If Needed)

**If something went wrong:**

1. **Stop VM containers:**
   ```bash
   docker compose -f docker-compose-mastercontainer.yaml down
   ```

2. **Start NAS containers:**
   ```bash
   ssh admin@<NAS-IP>
   sudo docker start nextcloud-aio-apache nextcloud-aio-nextcloud
   ```

3. **Disable maintenance on NAS:**
   ```bash
   sudo docker exec -u www-data nextcloud-aio-nextcloud php occ maintenance:mode --off
   ```

4. **Update Nginx** to point back to `<NAS-IP>:11000`

5. **Test:** `https://nextcloud.infinitylabs.co.il`

**Rollback time:** 15-30 minutes

---

## 📝 Migration Notes

**What worked well:**
- ___________________________________________
- ___________________________________________

**Issues encountered:**
- ___________________________________________
- ___________________________________________

**Time spent on each phase:**
- Phase 1 (NAS): ______
- Phase 2 (VM Prep): ______
- Phase 3 (AIO Install): ______
- Phase 4 (Data Migration): ______
- Phase 5 (Verification): ______
- Phase 6 (Nginx): ______
- Phase 7 (Go Live): ______

**Completed by:** ________________
**Date:** ________________
**Sign-off:** ________________

---

**Congratulations! Your Nextcloud is now running on a dedicated VM with optimal performance.** 🚀
