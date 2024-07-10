#!/usr/bin/env bash

set -eu -o pipefail

# be verbose
set -x
PS4='>>>\t '

# Configuration
ID=${1:-"6abaf08ac644c7ad"} # Default SHA1 (echo -n "dotcodeschool" | openssl dgst -sha1 | cut -d' ' -f2 | cut -b -16)
TAP_DEV="tap_${ID:0:11}" # Unique TAP device name based on VM ID - this must match the TAP_DEV variable in manage_network.sh
# Create user and get UID
_UID=$(sudo ./manage_users.sh --create "${ID}") || { echo "Failed to create user"; sudo ./cleanup.sh --vm-id "${ID}"; exit 1; }
GID=$_UID

EXEC_FILE="/usr/bin/firecracker"
JAILER_DIR="/srv/jailer/firecracker"
INSTANCE_DIR="${JAILER_DIR}/${ID}"
DATA_DIR="/var/lib/firecracker/data"

# Create the jailer directory required to run firecracker if it doesn't exist
mkdir -pv $JAILER_DIR

# Remove any pre-existing instance directory with same ID to allow jailer to create a new firecracker instance with the same ID - useful for booting a VM with the same ID for a given repo after exiting to minimize resource consumption
if [ -e $INSTANCE_DIR ]
then
        rm -rf $INSTANCE_DIR
fi

# Run jailer as a daemon
if jailer --id $ID \
       --exec-file $EXEC_FILE \
       --uid $_UID \
       --gid $GID \
       --daemonize
then
        echo "VM with ID ${ID} for user ${_UID} in group ${GID} successfully created! :D"
else
        echo "Failed to created VM! :("
        sudo ./cleanup.sh --vm-id $ID
        exit 1
fi

sudo ./manage_network.sh --cleanup $ID
sudo ./manage_network.sh --setup $ID

API_SOCKET="${INSTANCE_DIR}/root/run/firecracker.socket"
LOGFILE="${INSTANCE_DIR}/root/firecracker.log"

# Create log file
touch $LOGFILE
IMAGES_DIR="/var/lib/firecracker/images"

cp -R "${IMAGES_DIR}/." "${INSTANCE_DIR}/root"

# Create and move filesystem

sudo ./manage_fs.sh --create "$ID" || { echo "Failed to create filesystem"; sudo ./cleanup.sh --vm-id "$ID"; exit 1; }
sudo ./manage_fs.sh --move-in "$ID" || { echo "Failed to move filesystem"; sudo ./cleanup.sh --vm-id "$ID"; exit 1; }

chown -R $_UID:$GID "${INSTANCE_DIR}/root"

# Set log file
sudo curl -X PUT --unix-socket "${API_SOCKET}" \
    --data "{
        \"log_path\": \"./firecracker.log\",
        \"level\": \"Debug\",
        \"show_level\": true,
        \"show_log_origin\": true
    }" \
    "http://localhost/logger"

KERNEL="./vmlinux-6.1.97"
KERNEL_BOOT_ARGS="console=ttyS0 reboot=k panic=1 pci=off"

ARCH=$(uname -m)

if [ ${ARCH} = "aarch64" ]; then
    KERNEL_BOOT_ARGS="keep_bootcon ${KERNEL_BOOT_ARGS}"
fi

# Set boot source
sudo curl -X PUT --unix-socket "${API_SOCKET}" \
    --data "{
        \"kernel_image_path\": \"${KERNEL}\",
        \"boot_args\": \"${KERNEL_BOOT_ARGS}\"
    }" \
    "http://localhost/boot-source"

ROOTFS="./ubuntu-22.04.squashfs"
USERFS="./userfs.ext4"

# Set userfs
sudo curl -X PUT --unix-socket "${API_SOCKET}" \
    --data "{
        \"drive_id\": \"userfs\",
        \"path_on_host\": \"${USERFS}\",
        \"is_root_device\": false,
        \"is_read_only\": false
    }" \
    "http://localhost/drives/userfs"

# Set rootfs
sudo curl -X PUT --unix-socket "${API_SOCKET}" \
    --data "{
        \"drive_id\": \"rootfs\",
        \"path_on_host\": \"${ROOTFS}\",
        \"is_root_device\": true,
        \"is_read_only\": false
    }" \
    "http://localhost/drives/rootfs"

# Set machine configuration
sudo curl -X PUT --unix-socket "${API_SOCKET}" \
    --data "{
        \"vcpu_count\": 4,
        \"mem_size_mib\": 4096
    }" \
    "http://localhost/machine-config"

# The IP address of a guest is derived from its MAC address with
# `fcnet-setup.sh`, this has been pre-configured in the guest rootfs. It is
# important that `TAP_IP` and `FC_MAC` match this.
FC_MAC=$(sudo ./manage_network.sh --get-fc-mac $ID)

# Set network interface
sudo curl -X PUT --unix-socket "${API_SOCKET}" \
    --data "{
        \"iface_id\": \"net1\",
        \"guest_mac\": \"$FC_MAC\",
        \"host_dev_name\": \"$TAP_DEV\"
    }" \
    "http://localhost/network-interfaces/net1"

# API requests are handled asynchronously, it is important the configuration is
# set, before `InstanceStart`.
sleep 0.015s

# Start microVM
sudo curl -X PUT --unix-socket "${API_SOCKET}" \
    --data "{
        \"action_type\": \"InstanceStart\"
    }" \
    "http://localhost/actions"

FC_IP=$(sudo ./manage_network.sh --get-fc-ip $ID)
TAP_IP=$(sudo ./manage_network.sh --get-tap-ip $ID)

# API requests are handled asynchronously, it is important the microVM has been
# started before we attempt to SSH into it.
sleep 3s

MOUNT_POINT="/tmp/dotcodeschool"

# Setup internet access in the guest
ssh -i /var/lib/firecracker/images/ubuntu-22.04.id_rsa root@$FC_IP  <<EOF
ip route add default via $TAP_IP dev eth0

# Mount the user filesystem
mkdir -p $MOUNT_POINT && mount /dev/vdb $MOUNT_POINT

# Make .cargo directory in the user filesystem
mkdir -p $MOUNT_POINT/.cargo

# Copy .cargo directory files to the user filesystem and set cargo home
cp -ru /root/.cargo/. $MOUNT_POINT/.cargo
export CARGO_HOME=$MOUNT_POINT/.cargo
cd $MOUNT_POINT/repo && cargo test
EOF

# SSH into the microVM
ssh -i /var/lib/firecracker/images/ubuntu-22.04.id_rsa -t root@$FC_IP "cd $MOUNT_POINT/repo && echo 'Welcome to the Dot Code School VM!'; bash"

# Use `root` for both the login and password.
# Run `reboot` to exit.
