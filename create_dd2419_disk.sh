#!/bin/bash

# Define colors
BLACK='\033[0;30m'
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

echo ""
echo Script name: $0
echo Number of argument: $#
echo ""
echo ""

if [[ `id -u` != 0 ]]; then
	echo -e "${RED}ERROR! You must run this script as root${NC}"
	echo ""
	echo "Exiting..."
	echo ""	
	exit
fi

if (( $# != 3 )); then
	echo -e "${RED}ERROR! Incorrect number of parameters${NC}"
	echo "Usage: $0 path_to_folder disk_to_install_to PC_or_Mac"
	echo "Ex   : $0 ./DD2419_Disk_Master_PC /dev/sdb PC"
	echo ""
	echo "Exiting..."
	echo ""
    exit
fi

folder=$1
disk=$2
computer_type=$3

echo ""
echo "You have asked to make a new DD2419 external disk"
echo "Source folder   : " $folder
echo "Destination disk: " $disk
echo "Computer type   : " $computer_type
echo ""


if (( ${#disk} != 8 )); then
	echo -e "${RED}ERROR! Incorrect disk name ${NC}"
	echo "Disk name must have 8 characters, such as /dev/sdb"
	echo ""
	echo "Exiting..."
	echo ""
	exit
fi

if [[ "$computer_type" != "PC" ]]; then
	if [[ "$computer_type" != "Mac" ]]; then
		echo -e "${RED}ERROR! Incorrect computer type ${NC}"
		echo "Computer type cannot be $computer_type, must be PC or Mac"
		echo ""
		echo "Exiting..."
		echo ""
		exit
	fi	
fi

if [ "$disk" == "/dev/sda" ]; then
	echo -e "${RED}ERROR! Refusing to install on $disk ${NC}"
	echo -e "${RED}Too dangerous!!!! ${NC}"
	echo ""
	echo "Exiting..."
	echo ""
	exit
fi

shortdisk=${disk:5}
echo "Short disk name:" $shortdisk


echo "Content of source folder is"
ls -lh $folder 
echo ""
echo ""

echo "Looking for image files..."
for i in "1" "2"; do
	img="sdb${i}_${computer_type}.img"
	if [ ! -f "$folder/$img" ]; then
		echo -e "${RED}ERROR! Could not find file $img in source folder${NC}"
    	echo ""
		echo "Exiting..."
		echo ""
	    exit
	else
		echo "Found file $img. Check!"
	fi
done

echo ""
echo ""
echo -e "${GREEN}The connected disk reported by the system (${PURPLE}NOTE may not be in order${NC})"
parted -l |grep Model
echo ""
echo ""

echo -e "${GREEN}Current state of the destination disk${NC}"
fdisk -l $disk
echo ""
echo ""

diskinfo=`parted -l | grep -1 $disk`
echo -e "${GREEN}Disk info for $disk${NC}"
echo -e "${YELLOW}$diskinfo ${NC}"
echo ""

only_allowed_brand="Samsung Portable SSD T5 (scsi)"
#only_allowed_brand="Seagate BUP Slim WH (scsi)"
if [[ -z `echo ${diskinfo} | grep "${only_allowed_brand}"` ]]; then
	echo -e "${RED}ERROR! Refusing to install on this disk.${NC}"
	echo -e "${PURPLE}Only installing on disks of type $only_allowed_brand${NC}"
    echo ""
	echo "Exiting..."
	echo ""
    exit
fi

read -r -p "Do you want to perform the installation? [y/N] :" response
echo -e "${NC}"
case "$response" in
	[yY][eE][sS]|[yY]) 
    ;;
*)
	echo ""
    echo "ABORTED script without action"
    echo ""
    exit
    ;;
esac

sgdiskfile=`ls -1 ${folder}/*.sgdisk`
echo "Rewriting the partition table"
sgdiskoutputfile="/tmp/sgdiskoutput"
rm -f ${sgdiskoutputfile}
sgdisk -g --load-backup=${sgdiskfile} ${disk} > ${sgdiskoutputfile}
cat ${sgdiskoutputfile}

if grep -Fxq "Warning: The kernel is still using the old partition table." "${sgdiskoutputfile}"
then
	echo -e "${RED}WARNING: Kernel not aware of new partition${NC}"
	echo "Running partprobe"
	partprobe

	echo -e "${PURPLE}Showing current partition table${NC}"
	fdisk -l ${disk}

	read -r -p "Do you want to continue? [y/N] :" response
	echo -e "${NC}"
	case "$response" in [yY][eE][sS]|[yY]) 
   		;;
		*)
		echo ""
   		echo "ABORTED script "
   		echo ""
   		exit
    	;;
	esac
else
	echo "Wating 1s..."
	sleep 2
fi

echo -e "${YELLOW}Making sure partitions are unmounted${NC}"
umount ${disk}1
umount ${disk}2

echo "Wating 1s..."
sleep 1

# Restore the data to the disks
echo -e "${YELLOW}Making swap space${NC}"
mkswap -U `cat ${folder}/uuid-sdb3.txt | sed -n '/sdb3/s/.* UUID=\"\([^\"]*\)\".*/\1/p'` ${disk}3
echo -e "${YELLOW}Restore UEFI partition${NC}"
dd if=${folder}/sdb1_${computer_type}.img of=${disk}1 bs=4096
echo -e "${YELLOW}Restore / partition. This will take a few minutes...${NC}"
dd if=${folder}/sdb2_${computer_type}.img of=${disk}2 bs=4096
echo "Wating 1s..."
sleep 1


# Grow the / partition to fill the whole space
# Warning this assumes a very specific geometry of the disk!!!!!
echo -e "${YELLOW}Grow / to 212GB${NC}"
if [[ "$computer_type" == "PC" ]]; then
	parted ${disk} resizepart 2 484792319s
else
	echo "NOT tested growing Mac partition"
	#	parted ${disk} resizepart 2 484792319s
fi
echo "Wating 1s..."
sleep 1

echo -e "${YELLOW}Check the disk${NC}"
e2fsck -f ${disk}2 
echo "Wating 1s..."
sleep 1

echo -e "${YELLOW}Resize filesystem to fill partition${NC}"
resize2fs ${disk}2 

echo "Wating 1s..."
sleep 1

echo -e "${YELLOW}Syncing disks${NC}"
sync

echo ""
echo "Done! (hopefully...)"
