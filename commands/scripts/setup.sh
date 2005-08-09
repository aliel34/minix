#!/bin/sh
#
#	setup 4.1 - install a MINIX distribution	Author: Kees J. Bot
#								20 Dec 1994

LOCALRC=/usr/etc/rc.local

PATH=/bin:/usr/bin
export PATH

usage()
{
    cat >&2 <<'EOF'
Usage:	setup		# Install a skeleton system on the hard disk.
	setup /usr	# Install the rest of the system (binaries or sources).

	# To install from other things then floppies:

	urlget http://... | setup /usr		# Read from a web site.
	urlget ftp://... | setup /usr		# Read from an FTP site.
	mtools copy c0d0p0:... - | setup /usr	# Read from the C: drive.
	dosread c0d0p0 ... | setup /usr		# Likewise if no mtools.
EOF
    exit 1
}

# No options.
while getopts '' opt; do usage; done
shift `expr $OPTIND - 1`

if [ "$USER" != root ]
then	echo "Please run setup as root."
	exit 1
fi

# Installing MINIX on the hard disk.

case "$0" in
/tmp/*)
    rm -f "$0"
    ;;
*)  cp -p "$0" /tmp/setup
    exec /tmp/setup
esac

# Find out what we are running from.
exec 9<&0 </etc/mtab			# Mounted file table.
read thisroot rest			# Current root (/dev/ram or /dev/fd?)
read fdusr rest				# USR (/dev/fd? or /dev/fd?p2)
exec 0<&9 9<&-

# What do we know about ROOT?
case $thisroot:$fdusr in
/dev/ram:/dev/fd0p2)	fdroot=/dev/fd0		# Combined ROOT+USR in drive 0
			;;
/dev/ram:/dev/fd1p2)	fdroot=/dev/fd1		# Combined ROOT+USR in drive 1
			;;
/dev/ram:/dev/fd*)	fdroot=unknown		# ROOT is some other floppy
			;;
/dev/fd*:/dev/fd*)	fdroot=$thisroot	# ROOT is mounted directly
			;;
*)			fdroot=$thisroot	# ?
esac

echo -n "\
This is the MINIX installation script.

Note 1: If the screen blanks, hit CTRL+F3 to select \"software scrolling\".
Note 2: If things go wrong then hit DEL and start over.
Note 3: Some questions have default answers, like this: [y]
	Simply hit ENTER if you want to choose that answer.
Note 4: If you see a colon (:) then you should hit ENTER to continue.
:"
read ret

echo " --- Step 1: Select keyboard type ---------------------------------"

echo "
What type of keyboard do you have?  You can choose one of:
"
ls -C /usr/lib/keymaps | sed -e 's/\.map//g' -e 's/^/    /'
echo -n "
Keyboard type? [us-std] "; read keymap
test -n "$keymap" && loadkeys "/usr/lib/keymaps/$keymap.map"

ok=""
while [ "$ok" = "" ]
do
echo "
 --- Step 2: Select your expertise level ---------------------------
"
	echo "Now you need to create a MINIX 3 partition on the hard disk."
	echo -n "Do you want to use (A)utomatic or the e(X)pert mode? [A] "
	read ch
	case "$ch" in
	[Aa]*)	auto="1"; ok="yes"; ;;
	'')	auto="1"; ok="yes"; ;;
	[Xx]*)	auto="";  ok="yes"; ;;
	*)	echo "Unrecognized response."; ok=""; ;;
	esac
done

primary=

if [ -z "$auto" ]
then
	# Expert mode
echo -n "
MINIX needs one primary partition of about 250 MB for a full install.
The maxium fill system currently supported is 4 GB.

If there is no free space on your disk then you have to choose an option:
   (1) Delete one or more partitions
   (2) Allocate an existing partition to MINIX 3
   (3) Exit setup and shrink a partition using a different OS

To make this partition you will be put in the editor \"part\".  Follow the
advice under the '!' key to make a new partition of type MINIX.  Do not
touch an existing partition unless you know precisely what you are doing!
Please note the name of the partition (e.g. c0d0p1, c0d1p3, c1d1p0) you
make.  (See the devices section in usage(8) on MINIX device names.)
:"
	read ret

	while [ -z "$primary" ]
	do
	    part || exit

	    echo -n "
Please finish the name of the primary partition you have created:
(Just type ENTER if you want to rerun \"part\")                   /dev/"
	    read primary
	done
else
	# Automatic mode
	while [ -z "$primary" ]
	do
		PF="/tmp/pf"
		if autopart -f$PF
		then	if [ -s "$PF" ]
			then
				bd="`cat $PF`"
				if [ -b "/dev/$bd" ]
				then	primary="$bd"
				else	echo "Funny device $bd from autopart."
				fi
			else
				echo "Didn't find output from autopart."
			fi 
		else	echo "Autopart tool failed. Trying again."
		fi
	done

fi

root=${primary}s0
swap=${primary}s1
usr=${primary}s2

hex2int()
{
    # Translate hexadecimal to integer.
    local h d i

    h=$1
    i=0
    while [ -n "$h" ]
    do
	d=$(expr $h : '\(.\)')
	h=$(expr $h : '.\(.*\)')
	d=$(expr \( 0123456789ABCDEF : ".*$d" \) - 1)
	i=$(expr $i \* 16 + $d)
    done
    echo $i
}
echo " --- Step 8: Select your Ethernet chip ----------------------------"

# Ask user about networking
echo ""
echo "MINIX currently supports the following Ethernet cards. Please choose: "
echo ""
echo "0. No Ethernet card (no networking)"
echo "1. Intel Pro/100"
echo "2. Realtek 8139 based card"
echo "3. Realtek 8029 based card (emulated by Qemu)"
echo "4. NE2000, 3com 503 or WD based card (NE2000 is emulated by Bochs)"
echo "5. A 3com 501 or 509"
echo "6. A different Ethernet card (no networking)"
echo ""
echo "With some cards, you'll have to edit $LOCALRC "
echo "after installing to the proper parameters."
echo ""
echo "You can always change your mind after the install."
echo ""
echo -n "Choice? "
read eth
driver=""
driverargs=""
case "$eth" in
	1)	driver=fxp;      ;;
	2)	driver=rtl8139;  ;;
	3)	driver=dp8390;   driverargs="dp8390_args='DPETH0=pci'";	;;
	4)	driver=dp8390;   driverargs="#dp8390_args='DPETH0=port:irq:memory'"; echo "Note: After installing, please edit $LOCALRC to the right configuration."; 	;;
	5)	driver=dpeth;    ;;
esac

# Compute the amount of memory available to MINIX.
memsize=0
ifs="$IFS"
IFS=','
set -- $(sysenv memory)
IFS="$ifs"

for mem
do
    mem=$(expr $mem : '.*:\(.*\)')
    memsize=$(expr $memsize + $(hex2int $mem) / 1024)
done

# Compute an advised swap size.
swapadv=0
case `arch` in
i86)
    test $memsize -lt 4096 && swapadv=$(expr 4096 - $memsize)
    ;;
*)  test $memsize -lt 6144 && swapadv=$(expr 6144 - $memsize)
esac

blockdefault=8
echo " --- Step 9: Select a disk block size -----------------------------"

echo "The default block size on the disk is $blockdefault KB.
If you have a small disk or small RAM you may want less
than $blockdefault KB. Please type 1, 2, or 4 for a smaller
block size (in KB), or hit ENTER for the default of 
$blockdefault KB blocks, which should be fine in most cases."

while [ -z "$blocksize" ]
do	echo -n "Block size [$blockdefault KB]? "
	read blocksize
	if [ -z "$blocksize" ]
	then	blocksize=$blockdefault
	fi
	if [ "$blocksize" -ne 1 -a "$blocksize" -ne 2 -a "$blocksize" -ne 4 -a "$blocksize" -ne $blockdefault ]
	then	echo "$blocksize bogus block size. 1, 2, 4 or $blockdefault please."
		blocksize=""
	fi
done

blocksizebytes="`expr $blocksize '*' 1024`"
echo " --- Step 10: Allocate swap space ----------------------------------"

echo -n "How much swap space would you like?  Swapspace is only needed if this
system is memory starved. If you have 128 MB of memory or more, you
probably don't need it. If you have less and want to run many programs
at once, I suggest setting it to the memory size.

Size in kilobytes? [$swapadv] "
		    
swapsize=
read swapsize
test -z "$swapsize" && swapsize=$swapadv

echo "
 --- Step 11:  Check all your choices ----------------------------------
"

echo -n "You have created a partition named:	/dev/$primary
The following subpartitions are about to be created on /dev/$primary:

    Root subpartition:	/dev/$root	16 MB
    Swap subpartition:	/dev/$swap	$swapsize kb
    /usr subpartition:	/dev/$usr	rest of $primary

Hit ENTER if everything looks fine, or hit DEL to bail out if you want to
think it over.  The next step will destroy /dev/$primary.
:"
read ret
					# Secondary master bootstrap.
installboot -m /dev/$primary /usr/mdec/masterboot >/dev/null || exit

					# Partition the primary.
p3=0:0
test "$swapsize" -gt 0 && p3=81:`expr $swapsize \* 2`
partition /dev/$primary 1 81:32768* $p3 81:0+ || exit

if [ "$swapsize" -gt 0 ]
then
    # We must have that swap, now!
    mkswap -f /dev/$swap || exit
    mount -s /dev/$swap || exit
else
    # Forget about swap.
    swap=
fi

echo " --- Step 12: Wait for bad block detection ----------------------------"

mkfs -B $blocksizebytes /dev/$usr
echo "\
Scanning /dev/$usr for bad blocks.  (Hit DEL to stop the scan if you are
absolutely sure that there can not be any bad blocks.  Otherwise just wait.)"
trap ': nothing' 2
readall -b /dev/$usr | sh
sleep 2
trap 2

echo " --- Step 13: Wait for files to be copied ------------------------------"

mount /dev/$usr /mnt || exit		# Mount the intended /usr.

cpdir -v /usr /mnt || exit		# Copy the usr floppy.

umount /dev/$usr || exit		# Unmount the intended /usr.

umount $fdusr				# Unmount the /usr floppy.

mount /dev/$usr /usr || exit		# A new /usr

if [ $fdroot = unknown ]
then
    echo "
By now the floppy USR has been copied to /dev/$usr, and it is now in use as
/usr.  Please insert the installation ROOT floppy in a floppy drive."

    drive=
    while [ -z "$drive" ]
    do
	echo -n "What floppy drive is it in? [0] "; read drive

	case $drive in
	'')	drive=0
	    ;;
	[01])
	    ;;
	*)	echo "It must be 0 or 1, not \"$drive\"."
	    drive=
	esac
    done
    fdroot=/dev/fd$drive
fi

echo "
Copying $fdroot to /dev/$root
"

mkfs -B $blocksizebytes /dev/$root || exit
mount /dev/$root /mnt || exit
# Running from the installation CD.
cpdir -vx / /mnt || exit
chmod 555 /mnt/usr

# CD remnants that aren't for the installed system
rm /mnt/etc/issue /mnt/CD 2>/dev/null
					# Change /etc/fstab.
echo >/mnt/etc/fstab "\
# Poor man's File System Table.

root=/dev/$root
${swap:+swap=/dev/$swap}
usr=/dev/$usr"

					# National keyboard map.
test -n "$keymap" && cp -p "/usr/lib/keymaps/$keymap.map" /mnt/etc/keymap

# Set inet.conf to correct driver
if [ -n "$driver" ]
then	echo "eth0 $driver 0 { default; };" >/mnt/etc/inet.conf
	echo "$driverargs" >$LOCALRC
	disable=""
else	disable="disable=inet;"
fi

umount /dev/$root || exit		# Unmount the new root.

# Compute size of the second level file block cache.
case `arch` in
i86)
    cache=`expr "0$memsize" - 1024`
    test $cache -lt 32 && cache=0
    test $cache -gt 512 && cache=512
    ;;
*)
    cache=`expr "0$memsize" - 2560`
    test $cache -lt 64 && cache=0
    test $cache -gt 1024 && cache=1024
esac
echo "Second level file system block cache set to $cache kb."
if [ $cache -eq 0 ]; then cache=; else cache="ramsize=$cache"; fi

					# Make bootable.
installboot -d /dev/$root /usr/mdec/bootblock /boot/boot >/dev/null || exit
edparams /dev/$root "rootdev=$root; ramimagedev=$root; $disable $cache; main() { echo This is the MINIX 3 boot monitor.; echo MINIX will load in 5 seconds, or press ESC.; trap 5000 boot; menu; }; save" || exit
pfile="/usr/src/tools/fdbootparams"
echo "Remembering boot parameters in ${pfile}."
echo "rootdev=$root; ramimagedev=$root; $cache; save" >$pfile || exit
sync

echo "
Please type 'shutdown' to exit MINIX 3 and enter the boot monitor.
At the boot monitor prompt, you can type 'boot $primary' to try the
newly installed MINIX system.
See Part IV: Testing in the usage manual.
"

