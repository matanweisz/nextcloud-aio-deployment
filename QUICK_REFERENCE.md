# Quick Reference - Commands & Troubleshooting

> **Keep this open during migration for quick command lookup**

---

## 🔑 Essential Commands

### **Docker Compose (Mastercontainer)**
```bash
# Start mastercontainer
cd ~/nextcloud
docker compose -f docker-compose-mastercontainer.yaml up -d

# Stop mastercontainer
docker compose -f docker-compose-mastercontainer.yaml down

# View logs
docker compose -f docker-compose-mastercontainer.yaml logs -f

# Restart
docker compose -f docker-compose-mastercontainer.yaml restart
```

### **Get AIO Password**
```bash
docker logs nextcloud-aio-mastercontainer 2>&1 | grep "password"
```

### **Check Container Status**
```bash
# All containers
docker ps --filter name=nextcloud-aio --format "table {{.Names}}\t{{.Status}}"

# Only unhealthy
docker ps --filter name=nextcloud-aio --filter health=unhealthy
```

### **Nextcloud OCC Commands**
```bash
# Status
docker exec -u www-data nextcloud-aio-nextcloud php occ status

# Maintenance mode ON
docker exec -u www-data nextcloud-aio-nextcloud php occ maintenance:mode --on

# Maintenance mode OFF
docker exec -u www-data nextcloud-aio-nextcloud php occ maintenance:mode --off

# Scan files
docker exec --user www-data nextcloud-aio-nextcloud php occ files:scan --all

# List users
docker exec --user www-data nextcloud-aio-nextcloud php occ user:list
```

### **View Logs**
```bash
# Nextcloud logs
docker logs nextcloud-aio-nextcloud --tail 100

# Follow logs
docker logs -f nextcloud-aio-nextcloud

# Database logs
docker logs nextcloud-aio-database --tail 50

# Search for errors
docker logs nextcloud-aio-nextcloud | grep -i error | tail -20
```

### **NFS Mount**
```bash
# Check if mounted
df -h | grep nextcloud
mount | grep nextcloud

# Mount manually
sudo mount -a

# Remount
sudo umount /mnt/nas-nextcloud-data
sudo mount -a

# Test NFS from NAS
showmount -e <NAS-IP>
```

### **Check Resources**
```bash
# Container resource usage
docker stats --no-stream

# System resources
htop  # or top

# Disk space
df -h

# NFS usage
du -sh /mnt/nas-nextcloud-data
```

---

## 🐛 Common Issues & Solutions

### **Issue: Login Returns to Login Screen**

**Cause:** config.php values not migrated correctly

**Solution:**
```bash
# Check current values in config.php
docker exec nextcloud-aio-nextcloud grep -E "instanceid|passwordsalt|secret" /var/www/html/config/config.php

# Compare with extracted values
cat ~/nextcloud-migration/migration-secrets.txt

# If they don't match, edit config.php again (Step 20)
docker run -it --rm --volume nextcloud_aio_nextcloud:/var/www/html:rw alpine sh -c "apk add --no-cache nano && nano /var/www/html/config/config.php"
```

---

### **Issue: Files Not Visible**

**Cause:** NFS mount failed or database paths wrong

**Solution:**
```bash
# Check NFS mount
df -h | grep nextcloud
ls -la /mnt/nas-nextcloud-data/

# Check if Nextcloud container can see files
docker exec nextcloud-aio-nextcloud ls -la /mnt/ncdata/

# Rescan files
docker exec --user www-data nextcloud-aio-nextcloud php occ files:scan --all
```

---

### **Issue: Database Import Failed**

**Cause:** Database container keeps restarting

**Solution:**
```bash
# Check database logs
docker logs nextcloud-aio-database --tail 100

# If import failed, clear and retry:
docker run --rm --volume nextcloud_aio_database:/var/lib/postgresql/data:rw alpine sh -c "rm -rf /var/lib/postgresql/data/*"

# Copy dump again
docker cp ~/nextcloud-migration/database-dump.sql nextcloud-aio-database:/mnt/data/

# Remove cleanup marker
docker run --rm --volume nextcloud_aio_database_dump:/mnt/data:rw alpine rm -f /mnt/data/initial-cleanup-done

# Start containers via AIO interface
```

---

### **Issue: Upload Fails**

**Cause:** File size limit or permissions

**Solution:**
```bash
# Check upload limit in Nextcloud
docker exec -u www-data nextcloud-aio-nextcloud php occ config:system:get upload_limit

# Check NFS permissions
ls -lan /mnt/nas-nextcloud-data/ | head -10
# Should show UID 33

# Fix permissions if needed
sudo chown -R 33:33 /mnt/nas-nextcloud-data/
```

---

### **Issue: Nginx 502 Bad Gateway**

**Cause:** Can't reach VM or Apache not running

**Solution:**
```bash
# Check Apache container running on VM
docker ps | grep apache

# Check VM is reachable from Nginx server
# On Nginx:
curl -I http://<VM-IP>:11000

# Check VM firewall
sudo ufw status

# Check port listening on VM
sudo netstat -tlnp | grep 11000
```

---

### **Issue: Collabora Not Working**

**Cause:** Collabora container unhealthy or not configured

**Solution:**
```bash
# Check Collabora status
docker ps | grep collabora

# Check Collabora logs
docker logs nextcloud-aio-collabora --tail 50

# Activate Collabora config
docker exec -u www-data nextcloud-aio-nextcloud php occ richdocuments:activate-config

# Test Collabora endpoint
curl -I http://localhost:11000/browser
```

---

### **Issue: NFS Mount Drops**

**Cause:** Network issue or NFS service problem

**Solution:**
```bash
# Check if NFS server running on NAS
ssh admin@<NAS-IP> "sudo systemctl status nfs-server"

# Restart NFS on NAS if needed
ssh admin@<NAS-IP> "sudo systemctl restart nfs-server"

# Remount on VM
sudo umount /mnt/nas-nextcloud-data
sudo mount -a

# Check for errors
dmesg | grep nfs | tail -20
```

---

### **Issue: Container Won't Start**

**Cause:** Various (port conflict, volume issue, resource limits)

**Solution:**
```bash
# Check specific container logs
docker logs <container-name> --tail 50

# Check for port conflicts
sudo netstat -tlnp | grep <port>

# Check resources
docker stats --no-stream

# Restart via AIO interface
# Or restart specific container:
docker restart <container-name>
```

---

## 📊 Monitoring Commands

### **Health Checks**
```bash
# Quick health check
docker ps --filter name=nextcloud-aio --format "table {{.Names}}\t{{.Status}}"

# Nextcloud status
docker exec -u www-data nextcloud-aio-nextcloud php occ status

# Check for errors
docker logs nextcloud-aio-nextcloud --since 1h | grep -i error

# Database status
docker exec nextcloud-aio-database psql -U nextcloud -c "SELECT version();"
```

### **Performance Monitoring**
```bash
# Container resources
docker stats --no-stream

# System load
uptime

# Memory usage
free -h

# Disk I/O
iostat -x 1 5

# Network
iftop  # or netstat -i
```

### **Disk Usage**
```bash
# Docker volumes
docker system df -v

# NFS mount
df -h /mnt/nas-nextcloud-data

# Nextcloud data size
docker exec nextcloud-aio-nextcloud du -sh /mnt/ncdata

# Database size
docker exec nextcloud-aio-database psql -U nextcloud -d nextcloud_database -c "SELECT pg_size_pretty(pg_database_size('nextcloud_database'));"
```

---

## 🔧 Useful Paths

### **On Ubuntu VM**
```
Docker compose:     ~/nextcloud/docker-compose-mastercontainer.yaml
Migration files:    ~/nextcloud-migration/
NFS mount:          /mnt/nas-nextcloud-data/
Docker volumes:     /var/lib/docker/volumes/nextcloud_aio_*
Docker config:      /etc/docker/daemon.json
System config:      /etc/sysctl.d/99-nextcloud.conf
```

### **On NAS**
```
NFS export:         /volume1/nextcloud-vm-data/
Migration backup:   /volume1/nextcloud-migration/
```

### **Nginx Server**
```
Config:             /etc/nginx/sites-available/nextcloud.infinitylabs.co.il.conf
Logs:               /var/log/nginx/nextcloud.*.log
```

---

## 🚀 Performance Optimization

### **After Migration**
```bash
# Enable APCu cache
docker exec -u www-data nextcloud-aio-nextcloud php occ config:system:set memcache.local --value='\\OC\\Memcache\\APCu'

# Enable Redis cache
docker exec -u www-data nextcloud-aio-nextcloud php occ config:system:set memcache.distributed --value='\\OC\\Memcache\\Redis'

# Enable file locking
docker exec -u www-data nextcloud-aio-nextcloud php occ config:system:set filelocking.enabled --value=true --type=boolean

# Set cron for background jobs
docker exec -u www-data nextcloud-aio-nextcloud php occ background:cron

# Run background jobs manually
docker exec -u www-data nextcloud-aio-nextcloud php occ background:cron --run
```

---

## 🔄 Backup & Restore

### **Create Backup**
```bash
# Via AIO interface (preferred)
# Or manually trigger:
docker exec nextcloud-aio-mastercontainer /path/to/backup-script
```

### **List Backups**
```bash
ls -lh /mnt/nas-nextcloud-data/aio-backups/
```

### **Check Last Backup**
```bash
# Via AIO interface
# Or check files:
ls -lt /mnt/nas-nextcloud-data/aio-backups/ | head -5
```

---

## 📱 Testing Endpoints

### **Basic Health**
```bash
curl -I https://nextcloud.infinitylabs.co.il/status.php
# Should return: {"installed":true,"maintenance":false,...}
```

### **WebSocket (Talk)**
```bash
# In browser console (F12):
# Network tab → Filter: WS
# Should see WebSocket connections with status 101
```

### **Collabora**
```bash
curl -I https://nextcloud.infinitylabs.co.il/browser
# Should return: HTTP/2 200
```

---

## 🆘 Emergency Rollback

**Quick rollback to NAS:**
```bash
# 1. Stop VM
docker compose -f docker-compose-mastercontainer.yaml down

# 2. Start NAS (on NAS)
ssh admin@<NAS-IP> "sudo docker start nextcloud-aio-apache nextcloud-aio-nextcloud"

# 3. Disable maintenance (on NAS)
ssh admin@<NAS-IP> "sudo docker exec -u www-data nextcloud-aio-nextcloud php occ maintenance:mode --off"

# 4. Update Nginx config to point to NAS IP

# 5. Test
curl -I https://nextcloud.infinitylabs.co.il
```

---

## 📞 Getting Help

### **Check Logs First**
```bash
# All logs
docker compose -f docker-compose-mastercontainer.yaml logs

# Specific container
docker logs <container-name> --tail 100

# Follow logs
docker logs -f <container-name>

# Filter for errors
docker logs <container-name> | grep -i error
```

### **Get System Info**
```bash
# Docker version
docker --version
docker compose version

# System resources
free -h
nproc
df -h

# Network
ip addr show
route -n
```

### **Nextcloud Info**
```bash
# Version
docker exec -u www-data nextcloud-aio-nextcloud php occ --version

# Config check
docker exec -u www-data nextcloud-aio-nextcloud php occ config:list system

# Database check
docker exec -u www-data nextcloud-aio-nextcloud php occ db:status
```

---

## 💡 Tips

- **Always check logs first** when something fails
- **Verify one thing at a time** when troubleshooting
- **Use AIO interface** for container management (not direct docker commands)
- **Take notes** of any issues encountered
- **Don't skip verification steps** in STEP-BY-STEP.md
- **Keep this reference open** during migration

---

**This reference covers 95% of common issues. For detailed explanations, see full documentation.**
