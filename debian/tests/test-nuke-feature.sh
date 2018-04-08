#!/bin/sh

set -e

cd ${AUTOPKGTEST_TMP:-/tmp}

echo ">> Setup the 'cryptedfs' file that will contain the luks container"
dd if=/dev/zero of=cryptedfs count=1 bs=10M
echo -n "this the passphrase" >keyfile-default
echo -n "nuke it interactive" >keyfile-nuke-interactive
echo -n "nuke it keyfile" >keyfile-nuke-noninteractive

echo ">> Format with cryptsetup"
cryptsetup --batch-mode --verbose --use-urandom luksFormat cryptedfs keyfile-default

echo ">> Add nuke keys"
cat keyfile-default | cryptsetup --verbose luksAddNuke cryptedfs keyfile-nuke-interactive
cryptsetup --verbose luksAddNuke cryptedfs keyfile-nuke-noninteractive --key-file keyfile-default

echo ">> Open the luks container"
cryptsetup --verbose open cryptedfs testnuke --type luks --key-file keyfile-default
if [ ! -e /dev/mapper/testnuke ]; then
	echo "ERROR: /dev/mapper/testnuke has not been created"
	exit 1
fi

echo ">> Create the initial filesystem and put a flag file on it"
mkfs.ext4 /dev/mapper/testnuke
mount /dev/mapper/testnuke /mnt
echo "Debian rules!" >/mnt/my-secret-file
umount /mnt
cryptsetup --verbose close testnuke

echo ">> Backup the luks header"
rm -f luks-header-backup
cryptsetup --verbose luksHeaderBackup cryptedfs --header-backup-file luks-header-backup

test_nuke() {
    echo ">> Try to open the device with the nuke password from $1"
    RESULT=0
    cryptsetup --verbose open cryptedfs testnuke --type luks --key-file $1 || RESULT=$?
    if [ $RESULT = 0 ]; then
	echo "ERROR: open with nuke password worked!"
	set +e
	mount /dev/mapper/testnuke /mnt
	if [ -e /mnt/my-secret-file ]; then
	    echo "ERROR: and the flag file can be seen"
	fi
	umount /mnt
	cryptsetup --verbose close testnuke
	exit 1
    fi
    if [ -e /dev/mapper/testnuke ]; then
	echo "ERROR: /dev/mapper/testnuke should not exist"
	cryptsetup --verbose close testnuke
	exit 1
    fi
    if cryptsetup --verbose open cryptedfs testnuke --type luks --key-file keyfile-default; then
	echo "ERROR: open with default password worked!"
	cryptsetup --verbose close testnuke
	exit 1
    fi
    cryptsetup --batch-mode --verbose luksHeaderRestore cryptedfs --header-backup-file luks-header-backup
}
test_nuke keyfile-nuke-interactive
test_nuke keyfile-nuke-noninteractive
