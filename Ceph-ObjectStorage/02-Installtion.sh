## add nodes in hosts file:
cat <<EOF >> /etc/hosts 
192.168.100.60 node1
192.168.100.61 node2
192.168.100.62 node3
EOF

## disable firewall
systemctl stop firewalld
systemctl disable firewalld 
## disable selinux
setenforce 0
sed -i 's/^SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config


## chrony ntp server install and start
yum install chrony -y
systemctl enable chronyd --now
chronyc sources
## time sync check
timedatectl set-timezone Africa/Cairo
timedatectl set-timezone Asia/Shanghai
timedatectl status

#############################################################
## install cephadm on all nodes
CEPH_RELEASE=19.2.2
https://download.ceph.com/rpm-19.2.2/el9/noarch/cephadm
curl --silent --remote-name --location  https://download.ceph.com/rpm-$(CEPH_RELEASE)/el9/noarch/cephadm
chmod +x cephadm
./cephadm  add-repo --release 19.2.2
./cephadm install
which cephadm

#####################################
## Ruuning the bootstrap 
cephadm bootstrap --mon-ip  192.168.100.60  ## node1-ip
## Output output.txt

# from Web brwoser URL and cluster disks of node1


## How to add second node , can be add fro GUI
ssh-copy-id -f -i /etc/ceph/ceph.pub  root@node2
ssh-copy-id -f -i /etc/ceph/ceph.pub  root@node3

## add from CLI
cephadm shell
ceph orch host add node3 192.168.100.63

## add pool
# form GUI
from Pool --> Create Pool
# pool name : test_repl
# pool type : Replicated OR Erasure(parity(k+m)) # Ex: k2 m=2 , there 4 disks , can be failed 2 disks and data still available
# PG Auto Scale : on
# replication size : 3

# from CLI
ceph osd pool create test_erasure erasure --autoscale-mode=on

## How to add object on pool
rados --pool test_repl put messages files.txt
rados --pool test_repl ls
'files.txt'

## details about 
ceph osd map test_repl messages

#####################################################################################
############# Object Gateway (RGW) Installation Rados Gateway #############
# From GUI
# from Administration --> Service
# Type : rgw
# Name : rgw.s3
# Palce on : Hosts
# Zone : default
# Count: 3
# Port: 9000
# Create

# from CLI
ceph orch daemon add rgw default rgw.s3
ceph rgw zonegroup get default
ceph rgw zone get default

# systemctl list-units ceph-*
'crated pod for rgw.s3 on node1,2,3'

## Create Ingress for RGW S3
# from GUI
# Administration --> Service:
# Type : ingress
# Name : ingress.rgw
# Backend Type : rgw.s3
# Placement : Label
# Label: ingress
# Count: 1
# Virtual IP: 192.168.100.66
# Frontend Port: 9443
# Monitor Port: 9001
# CIDR Networks: 192.168.100.0/24
# Create

## On Node1
ip a 
'192.168.100.66/32'

# Create user for RGW S3
# from GUI
# from Object  --> User:
# User ID: s3-testuser01
# Full Name: S3 Test User 01
# checl Auto-generate access and secret key
# Create

## How to access RGW S3
# from any client
dnf install aws-cli OR 3cmd -y

s3cmd --configure
# Access Key: s3-testuser01's access key
# Secret Key: s3-testuser01's secret key
# Default Region: us-east-1
# S3 Endpoint: http://192.168.100.66:9443
# DNS-style : http://192.168.100.66:9443

s3cmd mb s3://testbucket
s3cmd ls
s3cmd put files.txt s3://testbucket
s3cmd ls s3://testbucket
s3cmd get s3://testbucket/files.txt files_downloaded.txt
cat files_downloaded.txt
radosgw-admin user info --uid=s3-testuser01
############# End of Object Gateway (RGW) Installation Rados Gateway #############


#############  Ceph File System (CephFS) Installation #############
# can create cephfs and mount on multi systems
# from CLI
cephadm shell
ceph fs volume create mycephfs
ceph fs ls
ceph fs status mycephfs

## How to mount cepfs on client
# from ceph server node1
ceph config generate-minimal-conf > /tmp/ceph.conf
# Create user to cephfs will using in client
ceph fs authorize mycephfs client.fsuser / rw
# copy output info to /tmp/ceph.client.fsuser.keyring and copy to client node to /etc/ceph/ceph.client.fsuser.keyring

## on Client node
# Add /etc/yum.repo.d/ceph.repo
cat <<EOF >> /etc/yum.repos.d/ceph.repo
[ceph]
name=Ceph packages for $basearch
baseurl=https://download.ceph.com/rpm-19.2.2/el9/$basearch
enabled=1
priority=2
gpgcheck=1
gpgkey=https://download.ceph.com/keys/release.asc

[ceph-noarch]
name=Ceph noarch packages
baseurl=https://download.ceph.com/rpm-19.2.2/el9/noarch
enabled=1
priority=2
gpgcheck=1
gpgkey=https://download.ceph.com/keys/release.asc

[ceph-source]
name=Ceph source packages
baseurl=https://download.ceph.com/rpm-19.2.2/el9/SRPMS
enabled=0
priority=2
gpgcheck=1
gpgkey=https://download.ceph.com/keys/release.asc  
EOF
yum provides mount.ceph
yum install ceph-common  -y

mkdir -p -m 755 /etc/ceph
scp root@node1:/tmp/ceph.conf /etc/ceph/ceph.conf
chmod 644 /etc/ceph/ceph.conf
chmod 600 /etc/ceph/ceph.client.fsuser.keyring
whereis mount.ceph

mkdir /mnt/mycephfs
mount -t ceph fsuser@.mycephfs=/ /mnt/mycephfs
df -hT /mnt/mycephfs
touch /mnt/mycephfs/hello_cephfs.txt
ls -l /mnt/mycephfs/hello_cephfs.txt
 
#################################################################################################
#############  End of Ceph File System (CephFS) Installation #############

############# RBD Block Device Installation #############
# from CLI
cephadm shell
ceph osd pool create rbdpool
ceph osd pool ls detail
#ceph osd pool application enable rbdpool rbd
rbd pool init rbdpool

ceph auth get-or-create client.rbduser mon  'profile rbd' osd 'profile rbd' mgr 'profile rbd'
# copy output to /etc/ceph/ceph.client.rbduser.keyring and copy to client node
rbd create --size 2048 rbdpool/disk1
rbd ls rbdpool
rbd info rbdpool/disk1
############# End of RBD Block Device Installation #############

## from Client node
scp root@node1:/etc/ceph/ceph.client.rbduser.keyring /etc/ceph/ceph.client.rbduser.keyring
chmod 600 /etc/ceph/ceph.client.rbduser.keyring 
rbd ls rbdpool --id client.rbduser
'dsk1'
lsblk
'not found disk1'
#rbd device map rbdpool/disk1 --id client.rbduser
rbd device map rbdpool/disk1 --id rbduser
'/dev/sbd0'
lsblk
'found disk1 as /dev/rdb0'

######################################################################
#####  Managing Clients Users#################################
