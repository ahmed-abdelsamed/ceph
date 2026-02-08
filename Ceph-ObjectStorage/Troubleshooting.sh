This error means Ceph can't find available storage devices for OSDs. Let's fix this step by step:

## 1. **Identify Available Disks**

```bash
# List all block devices
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL

# Detailed disk information
sudo fdisk -l
sudo parted -l

# Check for available disks (not mounted, no filesystem)
lsblk -dp | grep -o '^/dev[^ ]*' | xargs -I {} bash -c 'if ! mountpoint -q {}; then echo {}; fi'
```

## 2. **Prepare Disks for Ceph OSD**

### Option A: Use Whole Disk (Recommended)
```bash
# Check if disk has partitions
sudo parted /dev/sdb print

# If partitions exist, remove them
sudo wipefs -a /dev/sdb
sudo sgdisk --zap-all /dev/sdb
sudo dd if=/dev/zero of=/dev/sdb bs=1M count=100

# Verify disk is clean
sudo blkid /dev/sdb  # Should show nothing
sudo parted /dev/sdb print  # Should show no partitions
```

### Option B: Create Partition
```bash
# Create GPT partition table
sudo parted /dev/sdb mklabel gpt

# Create a single partition using all space
sudo parted -a optimal /dev/sdb mkpart primary 0% 100%

# Set partition type for Ceph
sudo parted /dev/sdb set 1 ceph data

# Verify
sudo parted /dev/sdb print
```

## 3. **Refresh Ceph Device List**

```bash
# Tell Ceph to rescan devices
sudo ceph orch device ls --refresh

# OR force refresh
sudo cephadm shell -- ceph orch device ls
```

## 4. **Manual OSD Creation**

If automatic detection still fails, create OSDs manually:

```bash
# Method 1: Using ceph-volume (traditional)
# Install ceph-volume tools
sudo dnf install -y ceph-osd

# Prepare the disk
sudo ceph-volume lvm zap /dev/sdb --destroy

# Create OSD
sudo ceph-volume lvm create --data /dev/sdb

# Method 2: Using cephadm shell
sudo cephadm shell

# Inside the shell:
ceph orch daemon add osd node1:/dev/sdb
# OR for multiple disks
ceph orch daemon add osd node1:/dev/sdb /dev/sdc /dev/sdd

# Exit shell
exit
```

## 5. **Using LVM for OSDs**

```bash
# Create physical volume
sudo pvcreate /dev/sdb

# Create volume group
sudo vgcreate ceph-vg /dev/sdb

# Create logical volume for OSD
sudo lvcreate -l 100%FREE -n osd-data ceph-vg

# Make Ceph use the LVM
sudo ceph-volume lvm create --data ceph-vg/osd-data
```

## 6. **Add Disks via Ceph Dashboard (GUI)**

If you have the dashboard enabled:
1. Open `https://node1:8443`
2. Login with admin credentials
3. Navigate to Cluster → OSDs → Create
4. Select available disks
5. Click "Create OSD"

## 7. **Verify and Monitor**

```bash
# Check OSD status
sudo ceph osd tree
sudo ceph osd stat
sudo ceph osd dump

# Check device status
sudo ceph orch device ls

# Watch OSD creation
sudo ceph -w
sudo journalctl -f -u ceph-osd@*
```

## 8. **Troubleshooting Commands**

```bash
# Check Ceph logs
sudo cephadm logs --name osd.<id>
sudo journalctl -u ceph-osd@0  # For osd.0

# Check if devices are blacklisted
sudo ceph osd crush rm-device-class <device_name>

# Reset device classes
sudo ceph osd crush set-device-class hdd *  # For HDDs
sudo ceph osd crush set-device-class ssd *  # For SSDs

# Force re-evaluation
sudo systemctl restart ceph-osd.target
```

## 9. **Common Issues and Solutions**

### Issue 1: Disk has existing filesystem
```bash
# Remove filesystem signatures
sudo wipefs -a /dev/sdb
sudo dd if=/dev/zero of=/dev/sdb bs=1M count=100
sudo blockdev --rereadpt /dev/sdb
```

### Issue 2: Disk is in use/mounted
```bash
# Unmount if mounted
sudo umount /dev/sdb1 2>/dev/null || true

# Check for LVM
sudo vgremove -f $(sudo pvs /dev/sdb --noheadings -o vg_name 2>/dev/null) 2>/dev/null || true
sudo pvremove /dev/sdb 2>/dev/null || true
```

### Issue 3: Permission issues
```bash
# Check disk permissions
ls -la /dev/sdb

# Ensure ceph user has access
sudo chown ceph:ceph /dev/sdb
sudo chmod 660 /dev/sdb
```

### Issue 4: Small disks (<5GB)
```bash
# Ceph needs at least 5GB per OSD
# Check disk size
sudo fdisk -l /dev/sdb | grep Disk

# If disk is too small, use a different disk or
# Adjust minimum requirements (not recommended)
ceph config set osd osd_min_size 1G
```

## 10. **Quick Fix Script**

Create this diagnostic script:

```bash
cat > /tmp/fix_ceph_osd.sh << 'EOF'
#!/bin/bash
echo "=== CEPH OSD DIAGNOSTIC ==="
echo ""
echo "1. Checking available disks:"
echo "---------------------------"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL | grep -v loop
echo ""
echo "2. Checking disk partitions:"
echo "---------------------------"
for disk in $(lsblk -dp | grep -o '^/dev[^ ]*' | grep -v /dev/sr); do
    echo "=== $disk ==="
    sudo blkid $disk 2>/dev/null || echo "No filesystem"
    sudo parted $disk print 2>/dev/null | grep -E "^Number|^Partition Table" || echo "No partitions"
done
echo ""
echo "3. Checking Ceph device status:"
echo "------------------------------"
sudo ceph orch device ls 2>/dev/null || echo "Ceph not responding"
echo ""
echo "4. Cleaning a disk for Ceph (e.g., /dev/sdb):"
echo "--------------------------------------------"
read -p "Enter disk to clean (e.g., /dev/sdb): " disk
if [ -b "$disk" ]; then
    echo "Cleaning $disk..."
    sudo umount ${disk}* 2>/dev/null || true
    sudo wipefs -a $disk
    sudo sgdisk --zap-all $disk
    sudo dd if=/dev/zero of=$disk bs=1M count=100
    sudo blockdev --rereadpt $disk
    echo "Done!"
else
    echo "Disk $disk not found!"
fi
EOF

chmod +x /tmp/fix_ceph_osd.sh
sudo /tmp/fix_ceph_osd.sh
```

## 11. **Automated Disk Preparation**

```bash
# Prepare all unused disks for Ceph
for disk in $(lsblk -dpno NAME,SIZE,TYPE | grep -E "disk$" | awk '{print $1}'); do
    # Skip if mounted or has filesystem
    if mountpoint -q $disk || sudo blkid $disk >/dev/null 2>&1; then
        echo "Skipping $disk (in use)"
        continue
    fi
    
    echo "Preparing $disk for Ceph OSD..."
    sudo wipefs -a $disk
    sudo sgdisk --zap-all $disk
    sudo dd if=/dev/zero of=$disk bs=1M count=100
done

# Refresh Ceph
sudo ceph orch device ls --refresh
```

## **Most Common Solution:**

Usually, the issue is that disks have existing partitions or filesystems. Run this:

```bash
# For each disk you want to use (e.g., /dev/sdb, /dev/sdc)
DISK="/dev/sdb"

# 1. Clean the disk
sudo wipefs -a $DISK
sudo sgdisk --zap-all $DISK
sudo dd if=/dev/zero of=$DISK bs=1M count=100
sudo blockdev --rereadpt $DISK

# 2. Refresh Ceph
sudo ceph orch device ls --refresh

# 3. Create OSD
sudo ceph orch daemon add osd $(hostname):$DISK
```

**Run this command first and share the output:**
```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL,ROTA
```

This will show exactly what disks you have available and their current state.