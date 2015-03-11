#!/sbin/bbx sh

exec 1<&-
exec 2<&-
exec 1<>/dev/kmsg
exec 2>&1

# remount root as rw
/sbin/bbx mount -o remount,rw rootfs
/sbin/bbx mkdir /ss
/sbin/bbx chmod 777 /ss

# mount safestrap partition
/sbin/bbx mount -t vfat -o uid=1023,gid=1023,fmask=0007,dmask=0007,allow_utime=0020 /dev/block/emstorage /ss

SLOT_LOC=$(/sbin/bbx cat /ss/safestrap/active_slot)

if [ "$SLOT_LOC" != "stock" ]; then
# move real partitions out of the way
/sbin/bbx mv /dev/block/system /dev/block/systemorig
/sbin/bbx mv /dev/block/userdata /dev/block/userdataorig
/sbin/bbx mv /dev/block/cache /dev/block/cacheorig

if ! test -e "/ss/safestrap/$SLOT_LOC/system.img.enc"; then
	# create SS loopdevs
	/sbin/bbx mknod -m600 /dev/block/loop-system b 7 99
	/sbin/bbx mknod -m600 /dev/block/loop-userdata b 7 98
	/sbin/bbx mknod -m600 /dev/block/loop-cache b 7 97
	
	# setup loopbacks
	/sbin/bbx losetup /dev/block/loop-system /ss/safestrap/$SLOT_LOC/system.img
	/sbin/bbx losetup /dev/block/loop-userdata /ss/safestrap/$SLOT_LOC/userdata.img
	/sbin/bbx losetup /dev/block/loop-cache /ss/safestrap/$SLOT_LOC/cache.img
	
	# change symlinks
	/sbin/bbx ln -s /dev/block/loop-system /dev/block/system
	/sbin/bbx ln -s /dev/block/loop-userdata /dev/block/userdata
	/sbin/bbx ln -s /dev/block/loop-cache /dev/block/cache
else
	CRYPTSETUPDIR="/sbin/local/cryptsetup"
	
	/sbin/bbx mknod -m600 /dev/block/loop-system-enc b 7 89
	/sbin/bbx mknod -m600 /dev/block/loop-userdata-enc b 7 88
	/sbin/bbx mknod -m600 /dev/block/loop-cache-enc b 7 87
	
	for part in system userdata cache; do
		/sbin/bbx losetup /dev/block/loop-"$part"-enc /ss/safestrap/"$SLOT_LOC"/"$part".img.enc
	done
	
	for I in 0; do # Try exactly 1 time. Add more words in order to increase the number of tries.
		read passphrase </dev/console
		for part in system userdata cache; do
			echo "$passphrase" | LD_LIBRARY_PATH="$CRYPTSETUPDIR" "$CRYPTSETUPDIR"/ld-linux.so.3 "$CRYPTSETUPDIR"/cryptsetup luksOpen /dev/block/loop-"$part"-enc "$part"
			if ! test -e /dev/mapper/"$part"; then
				break
			fi
		done
		if test -e /dev/mapper/system; then
			break
		fi
	done
	
	if test -e /dev/mapper/system; then # boot into private system
		for part in system userdata cache; do
			/sbin/bbx ln -s /dev/mapper/"$part" /dev/block/"$part"
		done
		
	else # boot into public system
		# create SS loopdevs
		/sbin/bbx mknod -m600 /dev/block/loop-system b 7 99
		/sbin/bbx mknod -m600 /dev/block/loop-userdata b 7 98
		/sbin/bbx mknod -m600 /dev/block/loop-cache b 7 97
		
		# setup loopbacks
		/sbin/bbx losetup /dev/block/loop-system /ss/safestrap/$SLOT_LOC/system.img
		/sbin/bbx losetup /dev/block/loop-userdata /ss/safestrap/$SLOT_LOC/userdata.img
		/sbin/bbx losetup /dev/block/loop-cache /ss/safestrap/$SLOT_LOC/cache.img
		
		# change symlinks
		/sbin/bbx ln -s /dev/block/loop-system /dev/block/system
		/sbin/bbx ln -s /dev/block/loop-userdata /dev/block/userdata
		/sbin/bbx ln -s /dev/block/loop-cache /dev/block/cache
	fi
fi
else
/sbin/bbx umount /ss
fi
