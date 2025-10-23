# Pre-Migration Validation Checklist

## 🎯 Purpose

**This checklist must be completed 1-2 days BEFORE the actual migration.**

By validating everything in advance, you prevent 90% of potential failures. Each item includes:
- ✅ What to check
- 🔧 How to test it
- ⚠️ What failure it prevents

**Estimated time to complete: 2-3 hours**

**Success Rate:**
- Without this validation: ~60% success rate
- With this validation: ~95% success rate

---

## 📋 Validation Categories

```
┌─────────────────────────────────────────┐
│ A. NAS Validation (10 checks)          │
├─────────────────────────────────────────┤
│ B. VM Validation (8 checks)            │
├─────────────────────────────────────────┤
│ C. Network Validation (6 checks)       │
├─────────────────────────────────────────┤
│ D. Storage Validation (5 checks)       │
├─────────────────────────────────────────┤
│ E. Current Nextcloud Validation (8 checks)│
├─────────────────────────────────────────┤
│ F. Backup Validation (5 checks)        │
├─────────────────────────────────────────┤
│ G. Documentation Validation (4 checks)  │
└─────────────────────────────────────────┘
Total: 46 validation checks
```

---

# A. NAS Validation

## A1. SSH Access Works

**What:** Verify SSH connectivity to NAS
**Prevents:** Failure 1.1 - SSH Access Lost

```bash
# Test SSH works
ssh admin@<NAS-IP> 'echo "SSH OK: $(date)"'
```

- [ ] ✅ SSH connection succeeds
- [ ] ✅ Can execute commands
- [ ] ✅ Know admin password (not relying only on keys)
- [ ] ✅ Alternative user access available (if possible)

**If fails:** Enable SSH in DSM → Terminal & SNMP

---

## A2. Current Nextcloud Version Identified

**What:** Know exact Nextcloud version on NAS
**Prevents:** Version mismatch issues

```bash
ssh admin@<NAS-IP> "sudo docker exec -u www-data nextcloud-aio-nextcloud php occ status"
```

- [ ] ✅ Version number recorded: `_____________`
- [ ] ✅ Version is supported by AIO
- [ ] ✅ Version matches latest AIO or is one version behind

**If fails:** Note version for troubleshooting later

---

## A3. config.php Extraction Works

**What:** Can extract critical config values
**Prevents:** Failure 1.2 - config.php Extraction Fails

```bash
# Test extraction
ssh admin@<NAS-IP> "sudo docker exec nextcloud-aio-nextcloud cat /var/www/html/config/config.php" > test-config.php

# Verify content
grep -E "instanceid|passwordsalt|secret" test-config.php
```

- [ ] ✅ config.php extracted successfully
- [ ] ✅ `instanceid` value found
- [ ] ✅ `passwordsalt` value found
- [ ] ✅ `secret` value found
- [ ] ✅ Values are not empty

**If fails:** Try docker cp method: `sudo docker cp nextcloud-aio-nextcloud:/var/www/html/config/config.php ~/`

---

## A4. Database Accessible and Size Known

**What:** Can connect to database and know size
**Prevents:** Failure 1.3 - Database Dump Fails

```bash
# Test database connection
ssh admin@<NAS-IP> "sudo docker exec nextcloud-aio-database psql -U nextcloud -l"

# Get database size
ssh admin@<NAS-IP> "sudo docker exec nextcloud-aio-database psql -U nextcloud -d nextcloud_database -c \"SELECT pg_size_pretty(pg_database_size('nextcloud_database'));\""
```

- [ ] ✅ Database connection works
- [ ] ✅ Database name confirmed: `_____________`
- [ ] ✅ Database size recorded: `_____________`
- [ ] ✅ Database size is reasonable (> 10MB, < 10GB typically)
- [ ] ✅ Can list tables: `\dt` command works

**If fails:** Check database container is running: `docker ps | grep database`

---

## A5. Test Database Dump Works

**What:** Perform test database dump
**Prevents:** Failure 1.3 - Database Dump Corrupts

```bash
# Test dump (schema only, fast)
ssh admin@<NAS-IP> "sudo docker exec nextcloud-aio-database pg_dump -U nextcloud nextcloud_database --schema-only" > test-schema-dump.sql

# Verify
grep "CREATE TABLE" test-schema-dump.sql | wc -l
```

- [ ] ✅ Test dump completes without errors
- [ ] ✅ Output file size > 0
- [ ] ✅ Contains table definitions (100+ tables)
- [ ] ✅ No error messages in dump

**If fails:** Try custom format: `pg_dump -Fc`

---

## A6. User Data Size and Location Known

**What:** Know where data is and how large
**Prevents:** Insufficient space planning

```bash
# Find data directory
ssh admin@<NAS-IP> "sudo docker exec -u www-data nextcloud-aio-nextcloud php occ config:system:get datadirectory"

# Get size
ssh admin@<NAS-IP> "sudo docker exec nextcloud-aio-nextcloud du -sh /mnt/ncdata"
```

- [ ] ✅ Data directory path recorded: `_____________`
- [ ] ✅ Data size recorded: `_____________`
- [ ] ✅ Size is reasonable and expected
- [ ] ✅ Know estimated migration time: `_____________`

**If fails:** Check container is running

---

## A7. NFS Service Available

**What:** NFS service is enabled and working
**Prevents:** Failure 1.4 - NFS Service Not Available

```bash
# Check NFS service
ssh admin@<NAS-IP> "sudo synoservicectl --status nfs-kernel-server"

# Or
ssh admin@<NAS-IP> "sudo systemctl status nfs-server"
```

- [ ] ✅ NFS service shows "running"
- [ ] ✅ NFS ports listening (111, 2049)
- [ ] ✅ Can export filesystem

**If fails:** Enable NFS in DSM → File Services → NFS

---

## A8. Sufficient Disk Space on NAS

**What:** Enough space for data + backups
**Prevents:** Failure 1.7 - Insufficient Disk Space

```bash
# Check free space
ssh admin@<NAS-IP> "df -h | grep volume1"
```

- [ ] ✅ Current disk usage recorded: `_____________`
- [ ] ✅ Free space recorded: `_____________`
- [ ] ✅ Free space > 2x data size
- [ ] ✅ At least 20% free space remaining after migration

**If fails:** Free up space or use different volume

---

## A9. NFS Export Can Be Created

**What:** Can create and configure NFS export
**Prevents:** NFS configuration issues

```bash
# Test creating test export
ssh admin@<NAS-IP> "sudo mkdir -p /volume1/test-nfs-export"
ssh admin@<NAS-IP> "sudo exportfs -o rw,no_root_squash <VM-IP>:/volume1/test-nfs-export"
ssh admin@<NAS-IP> "sudo exportfs -v"
```

- [ ] ✅ Test export created successfully
- [ ] ✅ Export appears in exportfs output
- [ ] ✅ VM IP is in allowed list
- [ ] ✅ Permissions are rw (read-write)

**If fails:** Check NFS service is running

---

## A10. Current Containers Are Healthy

**What:** All NAS containers running properly
**Prevents:** Migrating from unhealthy state

```bash
# Check container status
ssh admin@<NAS-IP> "sudo docker ps --filter name=nextcloud-aio --format 'table {{.Names}}\t{{.Status}}'"
```

- [ ] ✅ All containers show "Up" status
- [ ] ✅ Containers show "(healthy)" where applicable
- [ ] ✅ No containers restarting repeatedly
- [ ] ✅ Nextcloud web interface accessible and working

**If fails:** Fix issues before migration

---

# B. VM Validation

## B1. VM Resources Correct

**What:** VM has correct CPU, RAM, disk allocation
**Prevents:** Resource exhaustion during migration

```bash
# On VM, check resources
free -h
nproc
df -h /
```

- [ ] ✅ RAM: 16GB total: `_____________`
- [ ] ✅ vCPU: 12 cores: `_____________`
- [ ] ✅ Disk: 64GB: `_____________`
- [ ] ✅ Disk free space > 40GB: `_____________`

**If fails:** Adjust VM settings in Hyper-V

---

## B2. Network Connectivity Works

**What:** VM can reach NAS and internet
**Prevents:** Network-related failures

```bash
# Test connectivity
ping -c 4 <NAS-IP>
ping -c 4 8.8.8.8
ping -c 4 google.com
```

- [ ] ✅ Can ping NAS (< 1ms latency)
- [ ] ✅ Can ping internet
- [ ] ✅ DNS resolution works
- [ ] ✅ No packet loss

**If fails:** Check Hyper-V virtual switch configuration

---

## B3. Ubuntu Version Correct

**What:** Running Ubuntu 24.04 LTS
**Prevents:** Compatibility issues

```bash
# Check Ubuntu version
lsb_release -a
```

- [ ] ✅ Ubuntu 24.04 LTS confirmed
- [ ] ✅ System is up to date: `sudo apt update && sudo apt upgrade`
- [ ] ✅ No pending reboot required

**If fails:** Upgrade or reinstall OS

---

## B4. Docker NOT Installed Yet (or Snap Removed)

**What:** No docker installed, or proper docker only
**Prevents:** Failure 2.1 - Snap Docker Installed

```bash
# Check if docker is installed
which docker

# If installed, verify it's not snap
docker info | grep "Docker Root Dir"
```

- [ ] ✅ Docker not installed yet (preferred), OR
- [ ] ✅ Docker installed via official method (not snap)
- [ ] ✅ If snap Docker exists, plan to remove it
- [ ] ✅ Docker Root Dir is `/var/lib/docker` (not `/var/snap/`)

**If fails:** Remove snap docker before proceeding

---

## B5. Firewall Rules Planned

**What:** Know which ports to open
**Prevents:** Connectivity failures

```bash
# Check if UFW is active
sudo ufw status
```

- [ ] ✅ Firewall plan documented:
  - [ ] Port 8080 for AIO interface (from admin IPs)
  - [ ] Port 11000 for Apache (from Nginx IP)
  - [ ] Port 3478 TCP/UDP for Talk (public)
  - [ ] Port 2049 for NFS (from NAS IP)
- [ ] ✅ Nginx IP address known: `_____________`

**If fails:** Document firewall requirements

---

## B6. Hyper-V Integration Services Working

**What:** Integration services installed and working
**Prevents:** Performance and time sync issues

```bash
# Check integration services
lsmod | grep hv_
timedatectl status
```

- [ ] ✅ Hyper-V modules loaded
- [ ] ✅ Time synchronization active
- [ ] ✅ System clock synchronized: yes
- [ ] ✅ Enhanced session mode works (if desired)

**If fails:** Install linux-virtual and linux-cloud-tools-virtual packages

---

## B7. No Port Conflicts

**What:** Required ports are available
**Prevents:** Port conflict failures

```bash
# Check if ports are in use
sudo netstat -tlnp | grep -E '8080|11000|3478'
```

- [ ] ✅ Port 8080 is available (for AIO interface)
- [ ] ✅ Port 11000 is available (for Apache)
- [ ] ✅ Port 3478 is available (for Talk)
- [ ] ✅ No other services conflicting

**If fails:** Stop conflicting services or plan to use different ports

---

## B8. VM Time Zone Correct

**What:** Time zone set correctly
**Prevents:** Timestamp and scheduling issues

```bash
# Check timezone
timedatectl
```

- [ ] ✅ Timezone is correct: `Asia/Jerusalem` (or your timezone)
- [ ] ✅ Local time is accurate
- [ ] ✅ RTC in local TZ: no (should be UTC)

**If fails:** `sudo timedatectl set-timezone Asia/Jerusalem`

---

# C. Network Validation

## C1. NFS Mount Test from VM

**What:** VM can mount test NFS export from NAS
**Prevents:** Failure 2.4 - NFS Mount Fails

```bash
# On VM, test NFS mount
sudo apt update
sudo apt install -y nfs-common
showmount -e <NAS-IP>
sudo mkdir -p /mnt/test-nfs
sudo mount -t nfs <NAS-IP>:/volume1/test-nfs-export /mnt/test-nfs
```

- [ ] ✅ NFS client installed successfully
- [ ] ✅ showmount lists NFS exports
- [ ] ✅ Test mount succeeds
- [ ] ✅ Can read from mount: `ls /mnt/test-nfs`
- [ ] ✅ Can write to mount: `sudo touch /mnt/test-nfs/test`

**If fails:** Check NFS service, firewall, and export configuration

---

## C2. NFS Performance Test

**What:** NFS mount has acceptable performance
**Prevents:** Slow migration and poor production performance

```bash
# Test write speed
time sudo dd if=/dev/zero of=/mnt/test-nfs/testfile bs=1M count=1000
rm /mnt/test-nfs/testfile

# Test read speed
time sudo dd if=/mnt/test-nfs/testfile of=/dev/null bs=1M count=1000
```

- [ ] ✅ Write speed > 50 MB/s
- [ ] ✅ Read speed > 50 MB/s
- [ ] ✅ Latency < 10ms
- [ ] ✅ No connection drops during test

**If fails:** Check network configuration, consider using NFSv4, adjust mount options

---

## C3. Nginx Can Reach VM

**What:** Nginx server can connect to VM
**Prevents:** Failure 7.5 - Reverse Proxy Connection Failed

```bash
# On VM, start test web server
python3 -m http.server 11000 &
TEST_PID=$!

# From Nginx server:
curl -I http://<VM-IP>:11000

# Stop test server
kill $TEST_PID
```

- [ ] ✅ Nginx server can reach VM on port 11000
- [ ] ✅ Response time < 100ms
- [ ] ✅ No firewall blocking traffic

**If fails:** Check network routing, firewall rules, VM firewall

---

## C4. VM Can Resolve Domain

**What:** VM can resolve company domain
**Prevents:** DNS-related issues

```bash
# On VM
nslookup nextcloud.infinitylabs.co.il
host nextcloud.infinitylabs.co.il
```

- [ ] ✅ Domain resolves to correct IP
- [ ] ✅ DNS resolution is fast (< 1 second)
- [ ] ✅ Reverse DNS works (optional)

**If fails:** Configure DNS servers in /etc/resolv.conf or Hyper-V settings

---

## C5. Network Throughput Adequate

**What:** Network between VM and NAS has good throughput
**Prevents:** Slow data transfer

```bash
# Install iperf3 on both NAS and VM
# On NAS:
ssh admin@<NAS-IP> "docker run --rm --network host networkstatic/iperf3 -s" &

# On VM (after a few seconds):
iperf3 -c <NAS-IP> -t 30
```

- [ ] ✅ Throughput > 1 Gbps (gigabit network)
- [ ] ✅ Low jitter (< 1ms)
- [ ] ✅ No packet loss

**If fails:** Check network adapter settings, virtual switch configuration

---

## C6. SSL Certificates Valid on Nginx

**What:** SSL certificates are valid and match domain
**Prevents:** Certificate errors after migration

```bash
# From workstation
echo | openssl s_client -servername nextcloud.infinitylabs.co.il -connect nextcloud.infinitylabs.co.il:443 2>/dev/null | openssl x509 -noout -dates -subject
```

- [ ] ✅ Certificate is valid (not expired)
- [ ] ✅ Certificate matches domain
- [ ] ✅ Certificate chain is complete
- [ ] ✅ No expiration within next 30 days

**If fails:** Renew certificates before migration

---

# D. Storage Validation

## D1. NAS Has Sufficient Free Space

**What:** NAS has enough space for data + backups
**Prevents:** Failure 1.7 - Insufficient Disk Space

```bash
# Check space calculation
ssh admin@<NAS-IP> "df -h | grep volume1"

# Calculate needed space:
# - Current data: X GB
# - Migration backup: X GB
# - Database dump: ~1 GB
# - Buffer (20%): X * 0.2 GB
# Total needed: ~2.2X GB
```

- [ ] ✅ Free space calculated: `_____________`
- [ ] ✅ Space needed calculated: `_____________`
- [ ] ✅ Free space > Space needed
- [ ] ✅ At least 20% free space will remain

**If fails:** Free up space or use different volume

---

## D2. VM Has Sufficient Free Space

**What:** VM has enough space for Docker volumes
**Prevents:** Failure 2.5 - Insufficient Disk Space

```bash
# Check VM space
df -h /var/lib/docker

# Calculate needed space:
# - Docker images: ~5 GB
# - Database volume: ~10 GB
# - Nextcloud app: ~5 GB
# - Other volumes: ~2 GB
# - Temp/logs: ~5 GB
# - Buffer: ~15 GB
# Total needed: ~42 GB
```

- [ ] ✅ Free space: `_____________`
- [ ] ✅ Free space > 42GB
- [ ] ✅ VHD is fixed-size (not dynamic)
- [ ] ✅ VHD is on SSD (preferred)

**If fails:** Expand VM disk or clean up space

---

## D3. NFS Mount Options Tested

**What:** Optimal NFS mount options work
**Prevents:** Performance and reliability issues

```bash
# Test production mount options
sudo umount /mnt/test-nfs 2>/dev/null
sudo mount -t nfs -o vers=4.1,rsize=1048576,wsize=1048576,hard,timeo=600,retrans=2,actimeo=1 <NAS-IP>:/volume1/test-nfs-export /mnt/test-nfs

# Verify options
mount | grep test-nfs
```

- [ ] ✅ Mount succeeds with production options
- [ ] ✅ NFSv4.1 is used
- [ ] ✅ Large rsize/wsize work (1MB)
- [ ] ✅ Can still read and write

**If fails:** Adjust mount options, try NFSv3 if v4 fails

---

## D4. Disk I/O Performance Acceptable

**What:** VM disk has good I/O performance
**Prevents:** Slow Docker operations

```bash
# Test disk write speed
sudo dd if=/dev/zero of=/tmp/testfile bs=1G count=1 oflag=direct
rm /tmp/testfile

# Test disk read speed
sudo dd if=/dev/zero of=/tmp/testfile bs=1G count=1
sudo dd if=/tmp/testfile of=/dev/null bs=1G
rm /tmp/testfile
```

- [ ] ✅ Write speed > 100 MB/s (SSD: > 200 MB/s)
- [ ] ✅ Read speed > 200 MB/s (SSD: > 400 MB/s)
- [ ] ✅ VHD is on fast storage

**If fails:** Move VHD to SSD, use fixed-size VHD

---

## D5. File System Check Passed

**What:** VM file system is healthy
**Prevents:** File system corruption issues

```bash
# Check file system health (run during maintenance window)
# This requires reboot, so do it before migration day
sudo touch /forcefsck
sudo reboot

# After reboot, check results
sudo tail -100 /var/log/fsck
```

- [ ] ✅ File system check completed
- [ ] ✅ No errors found
- [ ] ✅ All inodes accessible

**If fails:** Fix file system errors before migration

---

# E. Current Nextcloud Validation

## E1. Current Nextcloud Accessible

**What:** Current Nextcloud is working properly
**Prevents:** Migrating from broken state

```bash
# Test from browser or curl
curl -L https://nextcloud.infinitylabs.co.il/status.php
```

- [ ] ✅ Nextcloud web interface accessible
- [ ] ✅ status.php returns installed:true, maintenance:false
- [ ] ✅ Can login successfully
- [ ] ✅ Files are accessible

**If fails:** Fix current Nextcloud before migrating

---

## E2. All Apps Up to Date

**What:** Nextcloud apps are updated
**Prevents:** Compatibility issues during migration

```bash
ssh admin@<NAS-IP> "sudo docker exec -u www-data nextcloud-aio-nextcloud php occ app:list"
```

- [ ] ✅ All apps show latest versions
- [ ] ✅ No apps marked as incompatible
- [ ] ✅ No apps with pending updates

**If fails:** Update all apps via Nextcloud admin interface

---

## E3. No Background Job Errors

**What:** Cron/background jobs running correctly
**Prevents:** Migrating with existing issues

```bash
ssh admin@<NAS-IP> "sudo docker exec -u www-data nextcloud-aio-nextcloud php occ status"
```

- [ ] ✅ Background jobs last run < 10 minutes ago
- [ ] ✅ No errors in background job log
- [ ] ✅ All background jobs completing successfully

**If fails:** Fix background job issues first

---

## E4. Database Integrity Check

**What:** Current database is healthy
**Prevents:** Migrating corrupt database

```bash
# Check database integrity
ssh admin@<NAS-IP> "sudo docker exec -u www-data nextcloud-aio-nextcloud php occ db:status"
```

- [ ] ✅ Database connection successful
- [ ] ✅ No integrity check errors
- [ ] ✅ Database tables accessible

**If fails:** Run database repair: `php occ maintenance:repair`

---

## E5. File Integrity Check

**What:** Files are not corrupted
**Prevents:** Migrating bad files

```bash
# Run integrity check (can take time)
ssh admin@<NAS-IP> "sudo docker exec -u www-data nextcloud-aio-nextcloud php occ integrity:check-core"
```

- [ ] ✅ Core integrity check passed
- [ ] ✅ No missing or corrupted files
- [ ] ✅ All file hashes match

**If fails:** Reinstall/repair Nextcloud before migration

---

## E6. Users Can Login

**What:** User authentication working
**Prevents:** Auth configuration issues

```bash
# Test with multiple users (not just admin)
```

- [ ] ✅ Admin can login
- [ ] ✅ Regular user can login
- [ ] ✅ LDAP working (if applicable)
- [ ] ✅ 2FA working (if enabled)

**If fails:** Fix auth issues before migration

---

## E7. External Storage Working (if applicable)

**What:** External storage mounts accessible
**Prevents:** Losing external storage configuration

```bash
# Check external storage
ssh admin@<NAS-IP> "sudo docker exec -u www-data nextcloud-aio-nextcloud php occ files_external:list"
```

- [ ] ✅ All external storage mounts listed
- [ ] ✅ All mounts show "ok" status
- [ ] ✅ External storage configuration documented

**If fails:** Fix or document external storage for reconfiguration

---

## E8. Mail Configuration Documented

**What:** Email settings are documented
**Prevents:** Losing mail configuration

```bash
# Extract mail config
ssh admin@<NAS-IP> "sudo docker exec nextcloud-aio-nextcloud grep -A 20 mail /var/www/html/config/config.php"
```

- [ ] ✅ SMTP server documented: `_____________`
- [ ] ✅ SMTP port documented: `_____________`
- [ ] ✅ SMTP credentials saved securely
- [ ] ✅ Mail from address documented

**If fails:** Document mail settings for manual reconfiguration

---

# F. Backup Validation

## F1. Full Backup Exists

**What:** Recent full backup of current Nextcloud
**Prevents:** Data loss if migration fails catastrophically

```bash
# Verify backup exists
ssh admin@<NAS-IP> "ls -lh /volume1/backups/nextcloud/"
```

- [ ] ✅ Backup exists and is recent (< 7 days)
- [ ] ✅ Backup size is reasonable
- [ ] ✅ Backup location documented: `_____________`
- [ ] ✅ Backup includes database + files

**If fails:** Create full backup NOW before proceeding

---

## F2. Backup Is Restorable

**What:** Backup has been tested
**Prevents:** Having unusable backup when needed

```bash
# Test restore (to test location, not production)
```

- [ ] ✅ Backup restore tested successfully
- [ ] ✅ Restored instance is functional
- [ ] ✅ All data present in restored backup
- [ ] ✅ Restore procedure documented

**If fails:** Fix backup system before migration

---

## F3. Backup Location Has Space

**What:** Backup destination has sufficient space
**Prevents:** Backup failures during migration

```bash
ssh admin@<NAS-IP> "df -h /volume1/backups"
```

- [ ] ✅ Backup location free space: `_____________`
- [ ] ✅ Space > 2x current data size
- [ ] ✅ Can create additional backups if needed

**If fails:** Free up space in backup location

---

## F4. Rollback Plan Documented

**What:** Know how to rollback if migration fails
**Prevents:** Extended downtime if something goes wrong

**Document rollback procedure:**
- [ ] ✅ Steps to stop VM containers written down
- [ ] ✅ Steps to restart NAS containers written down
- [ ] ✅ Steps to update Nginx config back written down
- [ ] ✅ Rollback tested in mind (not for real)

**If fails:** Document rollback procedure

---

## F5. Emergency Contacts Available

**What:** Know who to contact if major issues
**Prevents:** Delays in getting help

- [ ] ✅ Synology support contact: `_____________`
- [ ] ✅ Hyper-V admin contact: `_____________`
- [ ] ✅ Network admin contact: `_____________`
- [ ] ✅ Nextcloud community forum bookmarked

**If fails:** Document all emergency contacts

---

# G. Documentation Validation

## G1. IP Addresses Documented

**What:** All IP addresses are known and documented
**Prevents:** Configuration mistakes

- [ ] ✅ NAS IP: `_____________`
- [ ] ✅ VM IP: `_____________`
- [ ] ✅ Nginx IP: `_____________`
- [ ] ✅ Gateway IP: `_____________`
- [ ] ✅ DNS servers: `_____________`

**If fails:** Document all IPs before proceeding

---

## G2. Credentials Secured

**What:** All passwords/credentials are accessible
**Prevents:** Getting locked out during migration

- [ ] ✅ NAS admin password: `[SECURED]`
- [ ] ✅ VM sudo password: `[SECURED]`
- [ ] ✅ Nextcloud admin password: `[SECURED]`
- [ ] ✅ Database password: `[SECURED]`
- [ ] ✅ Credentials stored in secure location (password manager)

**If fails:** Secure all credentials in password manager

---

## G3. Maintenance Window Scheduled

**What:** Downtime window scheduled and communicated
**Prevents:** User complaints and interference

- [ ] ✅ Maintenance window date: `_____________`
- [ ] ✅ Maintenance window time: `_____________`
- [ ] ✅ Duration estimate: `_____________`
- [ ] ✅ Users notified
- [ ] ✅ Email notification sent
- [ ] ✅ Slack/Teams notification sent (if applicable)

**If fails:** Schedule and communicate maintenance window

---

## G4. Migration Checklist Printed

**What:** Physical copy of migration guide available
**Prevents:** Losing access to guides if systems go down

- [ ] ✅ CORRECTED_MIGRATION_GUIDE.md printed or available offline
- [ ] ✅ FAILURE_PREVENTION_RECOVERY.md printed or available offline
- [ ] ✅ NGINX_REVERSE_PROXY.md printed or available offline
- [ ] ✅ All guides accessible on separate device (laptop/tablet)

**If fails:** Print or download all guides locally

---

# Final Validation Score

**Count your checkmarks:**

```
Total checks: 46
Completed: _______
Percentage: _______%

95-100%: Excellent - Proceed with confidence
85-94%:  Good - Review failed items
75-84%:  Fair - Fix critical failures before proceeding
< 75%:   Poor - DO NOT proceed with migration yet
```

---

# Critical Failures - DO NOT PROCEED if any of these fail:

1. [ ] A3: config.php extraction works
2. [ ] A4: Database accessible
3. [ ] A5: Test database dump works
4. [ ] A7: NFS service available
5. [ ] A8: Sufficient disk space on NAS
6. [ ] B1: VM resources correct
7. [ ] B2: Network connectivity works
8. [ ] C1: NFS mount test from VM succeeds
9. [ ] D1: NAS has sufficient free space
10. [ ] D2: VM has sufficient free space
11. [ ] E1: Current Nextcloud accessible
12. [ ] F1: Full backup exists
13. [ ] F2: Backup is restorable

**If any of these 13 critical checks fail, STOP and fix them before scheduling migration.**

---

# Next Steps After Validation

✅ **All checks passed?**
1. Schedule migration date/time
2. Send final notification to users
3. Review CORRECTED_MIGRATION_GUIDE.md one more time
4. Begin migration during maintenance window

❌ **Some checks failed?**
1. Fix all critical failures first
2. Re-run this validation checklist
3. Only proceed when 95%+ checks pass

---

**This validation took:** `_______` hours
**Ready to proceed:** [ ] YES [ ] NO
**Date validated:** `_____________`
**Validated by:** `_____________`

---

**Save this completed checklist** - you'll reference it during the migration!