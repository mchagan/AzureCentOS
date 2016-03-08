# Kickstart for provisioning a RHEL 6.5 Azure VM

# System authorization information
auth --enableshadow --passalgo=sha512

# Use graphical install
text

# Do not run the Setup Agent on first boot
firstboot --disable

# Keyboard layouts
keyboard us

# System language
lang en_US.UTF-8

# Network information
network --bootproto=dhcp

# Use network installation
url --url=http://vault.centos.org/6.5/os/x86_64/
repo --name="CentOS-Updates" --baseurl=http://vault.centos.org/6.5/updates/x86_64/

# Root password
rootpw --plaintext "to_be_disabled"

# System services
services --enabled="sshd,waagent,ntp,dnsmasq,hypervkvpd"

# System timezone
timezone Etc/UTC --isUtc

# Partition clearing information
clearpart --all --initlabel

# Clear the MBR
zerombr

# Disk partitioning information
part / --fstyp="ext4" --size=1 --grow --asprimary

# System bootloader configuration
bootloader --location=mbr --append="numa=off console=ttyS0,115200n8 earlyprintk=ttyS0,115200 rootdelay=300"

# Add OpenLogic repo
repo --name=openlogic --baseurl=http://olcentgbl.trafficmanager.net/openlogic/6/openlogic/x86_64/

# Firewall configuration
firewall --disabled

# Enable SELinux
selinux --enforcing

# Don't configure X
skipx

# Power down the machine after install
poweroff

%packages
@base
@console-internet
@core
@debugging
@directory-client
@hardware-monitoring
@java-platform
@large-systems
@network-file-system-client
@performance
@perl-runtime
@server-platform
ntp
dnsmasq
cifs-utils
sudo
python-pyasn1
parted
WALinuxAgent
-dracut-config-rescue

%end

%post --log=/var/log/anaconda/post-install.log

#!/bin/bash

# Disable the root account
# usermod root -p '!!'

# Remove unneeded parameters in grub
sed -i 's/ rhgb//g' /boot/grub/grub.conf
sed -i 's/ quiet//g' /boot/grub/grub.conf
sed -i 's/ crashkernel=auto//g' /boot/grub/grub.conf

# Set OL repos
curl -so /etc/yum.repos.d/CentOS-Base.repo https://raw.githubusercontent.com/szarkos/AzureBuildCentOS/master/config/CentOS-Base.repo
curl -so /etc/yum.repos.d/OpenLogic.repo https://raw.githubusercontent.com/szarkos/AzureBuildCentOS/master/config/OpenLogic.repo

# Import CentOS and OpenLogic public keys
curl -so /etc/pki/rpm-gpg/OpenLogic-GPG-KEY https://raw.githubusercontent.com/szarkos/AzureBuildCentOS/master/config/OpenLogic-GPG-KEY
rpm --import /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-6
rpm --import /etc/pki/rpm-gpg/OpenLogic-GPG-KEY

# Enable SSH keepalive
sed -i 's/^#\(ClientAliveInterval\).*$/\1 180/g' /etc/ssh/sshd_config

# Configure network
cat << EOF > /etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE=eth0
ONBOOT=yes
BOOTPROTO=dhcp
TYPE=Ethernet
USERCTL=no
PEERDNS=yes
IPV6INIT=no
EOF

cat << EOF > /etc/sysconfig/network
NETWORKING=yes
HOSTNAME=localhost.localdomain
EOF

# Backup system-auth
if [ ! -e /etc/pam.d/system-auth-ac; then
  cp /etc/pam.d/system-auth-ac /etc/pam.d/system-auth-ac.orig
fi

# Deploy new configuration
cat <<EOF > /etc/pam.d/system-auth-ac

auth        required      pam_env.so
auth        sufficient    pam_fprintd.so
auth        sufficient    pam_unix.so nullok try_first_pass
auth        requisite     pam_succeed_if.so uid >= 1000 quiet_success
auth        required      pam_deny.so

account     required      pam_unix.so
account     sufficient    pam_localuser.so
account     sufficient    pam_succeed_if.so uid < 1000 quiet
account     required      pam_permit.so

password    requisite     pam_pwquality.so try_first_pass local_users_only retry=3 authtok_type= ucredit=-1 lcredit=-1 dcredit=-1 ocredit=-1
password    sufficient    pam_unix.so sha512 shadow nullok try_first_pass use_authtok remember=5
password    required      pam_deny.so

session     optional      pam_keyinit.so revoke
session     required      pam_limits.so
-session     optional      pam_systemd.so
session     [success=1 default=ignore] pam_succeed_if.so service in crond quiet use_uid
session     required      pam_unix.so

EOF

# Disable persistent net rules
touch /etc/udev/rules.d/75-persistent-net-generator.rules
rm -f /lib/udev/rules.d/75-persistent-net-generator.rules /etc/udev/rules.d/70-persistent-net.rules

# Deprovision and prepare for Azure
/usr/sbin/waagent -force -deprovision

%end
