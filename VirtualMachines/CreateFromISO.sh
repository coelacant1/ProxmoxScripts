#!/bin/bash
#
# CreateFromISO.sh
#
# Downloads an ISO if not present, picks storages by default (largest available),
# and creates a Proxmox VM with user-specified or tier-based parameters.
#
# Usage (non-interactive example):
#   ./CreateFromISO.sh -n Win10 -I "http://example.com/windows10.iso" -s "local-lvm" -d 32 -b uefi -p t0h -v vmbr1
#
# Tier Profiles (memory in GiB, cores):
#   t0h: 64GB, 20 cores, host CPU
#   t0 : 64GB, 20 cores
#   t1h: 32GB, 12 cores, host CPU
#   t1 : 32GB, 12 cores
#   t2h: 16GB, 8 cores, host CPU
#   t2 : 16GB, 8 cores
#   t3h: 8GB,  4 cores, host CPU
#   t3 : 8GB,  4 cores
#
# If called without required arguments, it enters interactive mode:
#   1) Finds or asks for ISO storage.
#   2) Lists *both* local ISOs and CSV-based remote ISOs (pages of 20 items); user picks by number.
#   3) Prompts for VM parameters or tier selection.
#
# By default:
#  - Picks the largest storage that supports VM images or falls back to 'local-lvm'.
#  - Picks the largest storage that supports ISO or prompts the user if none found.
#  - Infers OS type from the ISO name (windows/linux).
#  - If Windows, adds TPM and a secondary VirtIO disk.
#
# Dependencies beyond default Proxmox 8: None (curl is included by default).
#

source "$UTILITIES"

###############################################################################
# pick_largest_storage_for_content: returns the storage ID with the most free space
# for a given content type (e.g., "iso", "images"). Falls back to empty if none found.
###############################################################################
function pick_largest_storage_for_content {
    local contentType="$1"
    local largestStore=""
    local largestFree=0

    while read -r line; do
        [[ "$line" =~ ^Name|^$ ]] && continue

        local storeId storeType storeStatus storeTotal storeUsed storeAvail storePct
        read -r storeId storeType storeStatus storeTotal storeUsed storeAvail storePct <<<"$line"
        [[ "$storeStatus" != "active" ]] && continue

        # Convert storeAvail (e.g. "200.1G") to a numeric in MiB
        local numericAvail
        if [[ "$storeAvail" =~ G$ ]]; then
            local withoutG="${storeAvail%G}"
            numericAvail=$(awk -v val="$withoutG" 'BEGIN {printf "%.0f", val*1024}')
        else
            # If no 'G' suffix, assume bytes and convert to MiB
            numericAvail=$((storeAvail / 1024 / 1024))
        fi

        if ((numericAvail > largestFree)); then
            largestFree="$numericAvail"
            largestStore="$storeId"
        fi
    done < <(pvesm status --content "$contentType" 2>/dev/null || true)

    echo "$largestStore"
}

###############################################################################
# parse_disk_size_gib:
#   - Strips a trailing 'G' or 'g' from user input (e.g., "32G" → "32").
#   - Checks if the remaining string is numeric.
#   - If not numeric, prints error and exits.
#   - Returns the numeric value (in GiB) to stdout.
###############################################################################
function parse_disk_size_gib {
    local userInput="$1"

    # Strip trailing "G" or "g" if present
    userInput="${userInput%[Gg]}"

    # Check if numeric
    if ! [[ "$userInput" =~ ^[0-9]+$ ]]; then
        echo "Error: Disk size \"$1\" is not a valid number (with optional trailing 'G')." >&2
        exit 1
    fi

    echo "$userInput"
}

###############################################################################
# disk_volume_id: determines how to specify disk size for LVM vs. dir storages
###############################################################################
function disk_volume_id {
    local store="$1"    # e.g. 'local-lvm'
    local sizeGib="$2"  # e.g. '32'

    # Check storage type
    local stType
    stType=$(pvesm status --storage "$store" 2>/dev/null | awk 'NR>1 {print $2}')
    # stType might be "lvmthin", "lvm", "dir", "nfs", etc.

    if [[ "$stType" == "lvmthin" || "$stType" == "lvm" ]]; then
        # LVM-based, no 'G' suffix
        echo "${store}:${sizeGib}"
    else
        # Directory-based, etc.
        echo "${store}:${sizeGib}G"
    fi
}

function show_predefined_tiers {
    echo "  Predefined Tiers:" >&2
    echo "    t0h => 64 GiB, 20 cores, host CPU" >&2
    echo "    t0  => 64 GiB, 20 cores" >&2
    echo "    t1h => 32 GiB, 12 cores, host CPU" >&2
    echo "    t1  => 32 GiB, 12 cores" >&2
    echo "    t2h => 16 GiB, 8 cores, host CPU" >&2
    echo "    t2  => 16 GiB, 8 cores" >&2
    echo "    t3h => 8 GiB, 4 cores, host CPU" >&2
    echo "    t3  => 8 GiB, 4 cores" >&2
}

###############################################################################
# prompt_for_parameters: asks user for VM name, ID, BIOS, disk size, etc.
###############################################################################
function prompt_for_parameters {
    while true; do
        echo -n "Enter VM name: " >&2
        read -r vmName
        if [[ -z "$vmName" ]]; then
            echo >&2 "Error: VM name cannot be empty. Please try again."
        else
            break
        fi
    done

    echo -n "Enter desired VM ID (leave empty to auto-generate): " >&2
    read -r vmId

    echo -n "UEFI or BIOS? [uefi/bios] (default: bios): " >&2
    read -r biosType
    [[ -z "$biosType" ]] && biosType="bios"

    echo -n "Enter disk size in GiB (e.g. 32 or 32G), default: 32G: " >&2
    read -r diskGiB
    [[ -z "$diskGiB" ]] && diskGiB="32G"
    diskGiB="$(parse_disk_size_gib "$diskGiB")"

    echo -n "Enter network bridge name (default: vmbr0): " >&2
    read -r bridgeName
    [[ -z "$bridgeName" ]] && bridgeName="vmbr0"

    show_predefined_tiers

    echo -n "Choose tier profile (t0h/t0/t1h/t1/t2h/t2/t3h/t3) or type 'custom': " >&2
    read -r tier

    local memoryGiB=""
    local cores=""
    local cpuModel="default"

    case "$tier" in
        t0h) memoryGiB=64; cores=20; cpuModel="host" ;;
        t0 ) memoryGiB=64; cores=20 ;;
        t1h) memoryGiB=32; cores=12; cpuModel="host" ;;
        t1 ) memoryGiB=32; cores=12 ;;
        t2h) memoryGiB=16; cores=8;  cpuModel="host" ;;
        t2 ) memoryGiB=16; cores=8 ;;
        t3h) memoryGiB=8;  cores=4;  cpuModel="host" ;;
        t3 ) memoryGiB=8;  cores=4 ;;
        custom)
            echo -n "Enter memory in GiB (default: 8): " >&2
            read -r customMem
            [[ -z "$customMem" ]] && customMem=8
            memoryGiB="$customMem"

            echo -n "Enter number of CPU cores (default: 8): " >&2
            read -r customCores
            [[ -z "$customCores" ]] && customCores=8
            cores="$customCores"

            echo -n "CPU model [host/default]? (default: default): " >&2
            read -r customModel
            [[ -z "$customModel" ]] && customModel="default"
            cpuModel="$customModel"
            ;;
        *)
            echo >&2 "Using default t3."
            memoryGiB=8
            cores=4
            ;;
    esac

    echo "$vmName|$vmId|$biosType|$diskGiB|$bridgeName|$memoryGiB|$cores|$cpuModel"
}

###############################################################################
# Attempt both possible CSV paths
###############################################################################
function find_csv_path {
    local path1="./ISOList.csv"
    local path2="./VirtualMachines/ISOList.csv"

    if [[ -f "$path1" ]]; then
        echo "$path1"
    elif [[ -f "$path2" ]]; then
        echo "$path2"
    else
        echo >&2 "Error: Could not find CSV file in either '$path1' or '$path2'."
        exit 1
    fi
}

###############################################################################
# pick_iso_local_or_remote:
#   1) Lists all local ISOs in localIsoStore as "Local: filename.iso".
#   2) Reads CSV-based remote links, displayed as "Remote: filename.iso".
#   3) Internally stores "###" delimiter so we can retrieve the full link if needed.
#   4) Merges both lists, shows them in pages of 20.
#   5) Returns the chosen item on stdout in the form:
#      "Local: file.iso###(no link)"
#      or
#      "Remote: file.iso###https://example.com/path/file.iso"
###############################################################################
function pick_iso_local_or_remote {
    local isoStore="$1"
    local csvPath="$(find_csv_path)"  # either ./ISOList.csv or ./VirtualMachines/ISOList.csv

    # 1) Gather local ISOs from "isoStore"
    local -a localIsos=()
    while IFS= read -r volId; do
        # volId might look like "local:iso/ubuntu-24.04.iso"
        # We only want the short name after "iso/"
        local shortName="${volId#*:iso/}"
        # For local, we have no real "URL" to store, so use "(no link)"
        localIsos+=( "Local: ${shortName}###(no link)" )
    done < <( pvesm list "$isoStore" 2>/dev/null | awk '$3 == "iso" {print $1}' )

    # 2) Gather remote links from CSV (now with 2 columns)
    local -a remoteIsos=()
    while IFS=, read -r dispName link; do
        # If the line or link is empty, skip
        [[ -z "$link" ]] && continue

        # If display name is empty, fallback to the actual base filename
        if [[ -z "$dispName" ]]; then
            dispName="$(basename "$link")"
        fi

        # We'll store the display name for the user, 
        # but keep the real link after ### so we can still download from it
        remoteIsos+=( "Remote: ${dispName}###${link}" )
    done < <( tr -d '\r' < "$csvPath" | grep -v '^[[:space:]]*$' )

    # 3) Merge both arrays
    local -a allItems=( "${localIsos[@]}" "${remoteIsos[@]}" )
    local total="${#allItems[@]}"
    if [[ "$total" -eq 0 ]]; then
        echo >&2 "No local ISOs or CSV links found."
        exit 1
    fi

    # 4) Paginate & pick
    local pageSize=20
    local page=0

    while true; do
        local start=$(( page * pageSize ))
        local end=$(( start + pageSize ))
        (( end > total )) && end="$total"

        echo >&2 "Available ISOs (page $((page + 1))):"
        for (( i=start; i<end; i++ )); do
            local idx=$(( i + 1 ))
            local displayPart="${allItems[$i]%%###*}"
            echo >&2 "  $idx) $displayPart"
        done

        echo -n >&2 "Pick a number (n=next, p=prev, q=quit): "
        read -r choice

        case "$choice" in
            n) (( page < (total-1)/pageSize )) && (( page++ )) ;;
            p) (( page > 0 )) && (( page-- )) ;;
            q)
                echo >&2 "Aborted."
                exit 1
                ;;
            ''|*[!0-9]*)
                echo >&2 "Invalid input. Please enter a number, or n/p/q."
                ;;
            *)
                local choiceNum=$(( choice ))
                if (( choiceNum >= 1 && choiceNum <= total )); then
                    local pickedIndex=$(( choiceNum - 1 ))
                    echo "${allItems[$pickedIndex]}"
                    return 0
                else
                    echo >&2 "Invalid range."
                fi
                ;;
        esac
    done
}

###############################################################################
# Main
###############################################################################
check_root
check_proxmox

# Parse optional arguments for non-interactive:
#   -n / -N  => VM_NAME
#   -l / -L  => ISO_URL
#   -s / -S  => VM_STORAGE
#   -d / -D  => DISK_GIB
#   -b / -B  => BIOS_TYPE
#   -p / -P  => TIER
#   -v / -V  => BRIDGE_NAME
#   -i / -I  => VM_ID
while getopts ":n:N:l:L:s:S:d:D:b:B:p:P:v:V:i:I:" opt; do
    case "${opt}" in
        n|N) VM_NAME="${OPTARG}" ;;
        l|L) ISO_URL="${OPTARG}" ;;
        s|S) VM_STORAGE="${OPTARG}" ;;
        d|D) DISK_GIB="${OPTARG}" ;;
        b|B) BIOS_TYPE="${OPTARG}" ;;
        p|P) TIER="${OPTARG}" ;;
        v|V) BRIDGE_NAME="${OPTARG}" ;;
        i|I) VM_ID="${OPTARG}" ;;
        *)
            echo "Unknown option -${opt}" >&2
            exit 1
            ;;
    esac
done

# If DISK_GIB empty in non-interactive mode, default to 32 GiB
if [[ -z "$DISK_GIB" ]]; then
    DISK_GIB="32"
fi
DISK_GIB="$(parse_disk_size_gib "$DISK_GIB")"

###############################################################################
# Interactive mode if essential arguments are missing
###############################################################################
if [[ -z "$VM_NAME" || -z "$ISO_URL" ]]; then
    echo >&2 "Entering interactive mode, not enough parameters..."

    # 1) Determine ISO storage
    echo >&2 "Determining ISO storage..."
    localIsoStore=$(pick_largest_storage_for_content "iso")
    if [[ -z "$localIsoStore" ]]; then
        mapfile -t isoStoreArray < <( pvesm status --content iso 2>/dev/null | awk 'NR>1 && $3=="active" {print $1}' )
        if (( ${#isoStoreArray[@]} == 1 )); then
            localIsoStore="${isoStoreArray[0]}"
        else
            if (( ${#isoStoreArray[@]} == 0 )); then
                echo >&2 "No storage with ISO support found."
                echo -n "Enter storage ID for ISO files: " >&2
                read -r userIsoStore
                localIsoStore="$userIsoStore"
            else
                echo >&2 "Multiple storages with ISO support found:"
                for st in "${isoStoreArray[@]}"; do
                    echo >&2 " - $st"
                done
                echo -n "Pick one: " >&2
                read -r userIsoStore
                localIsoStore="$userIsoStore"
            fi
        fi
    fi
    echo >&2 "Using ISO storage: '$localIsoStore'."

    # 2) Let user pick from local or remote CSV
    pickedIso="$(pick_iso_local_or_remote "$localIsoStore")"

    # We might have a string like:
    # "Local: ubuntu-24.04.iso###(no link)"
    # or
    # "Remote: file.iso###https://cdimage.debian.org/...file.iso"

    # Split at "###"
    labelPart="${pickedIso%%###*}"    # e.g. "Remote: file.iso"
    linkPart="${pickedIso#*###}"      # e.g. "https://cdimage.debian.org/...file.iso" or "(no link)"

    # Distinguish local vs. remote
    if [[ "$labelPart" == Local:* ]]; then
        # e.g. "Local: ubuntu-24.04.iso"
        isoName="${labelPart#Local: }"
        ISO_URL=""  # no remote link
    else
        # e.g. "Remote: file.iso"
        # Then the actual link is in linkPart
        isoName="$(basename "$linkPart")"
        ISO_URL="$linkPart"
    fi

    # 3) Prompt user for VM parameters
    readParams="$(prompt_for_parameters)"
    IFS='|' read -r pName pId pBios pDisk pBridge pMem pCores pCPU <<<"$readParams"
    VM_NAME="$pName"
    VM_ID="$pId"
    BIOS_TYPE="$pBios"
    DISK_GIB="$pDisk"
    BRIDGE_NAME="$pBridge"
    MEMORY_GIB="$pMem"
    CPU_CORES="$pCores"
    CPU_MODEL="$pCPU"
else
    # Non-interactive path
    MEMORY_GIB="8"
    CPU_CORES="4"
    CPU_MODEL="default"
    case "$TIER" in
        t0h) MEMORY_GIB=64; CPU_CORES=20; CPU_MODEL="host" ;;
        t0 ) MEMORY_GIB=64; CPU_CORES=20 ;;
        t1h) MEMORY_GIB=32; CPU_CORES=12; CPU_MODEL="host" ;;
        t1 ) MEMORY_GIB=32; CPU_CORES=12 ;;
        t2h) MEMORY_GIB=16; CPU_CORES=8;  CPU_MODEL="host" ;;
        t2 ) MEMORY_GIB=16; CPU_CORES=8 ;;
        t3h) MEMORY_GIB=8;  CPU_CORES=4;  CPU_MODEL="host" ;;
        t3 ) MEMORY_GIB=8;  CPU_CORES=4 ;;
        ""  ) ;;
        *)  echo >&2 "Unknown tier '$TIER'; using default t3." ;;
    esac
fi

###############################################################################
# Final fallback for VM disk storage and other fields if not set
###############################################################################
[ -z "$BIOS_TYPE" ] && BIOS_TYPE="bios"
[ -z "$VM_ID" ] && VM_ID=$(pvesh get /cluster/nextid)
[ -z "$BRIDGE_NAME" ] && BRIDGE_NAME="vmbr0"

if [[ -z "$VM_STORAGE" ]]; then
    VM_STORAGE=$(pick_largest_storage_for_content "images")
    [ -z "$VM_STORAGE" ] && VM_STORAGE="local-lvm"
fi

[ -z "$MEMORY_GIB" ] && MEMORY_GIB="8"
[ -z "$CPU_CORES" ] && CPU_CORES="4"
[ -z "$CPU_MODEL" ] && CPU_MODEL="default"

# If the user never picked localIsoStore in interactive mode, do it now
if [[ -z "$localIsoStore" ]]; then
    localIsoStore=$(pick_largest_storage_for_content "iso")
    [ -z "$localIsoStore" ] && localIsoStore="local"
fi

###############################################################################
# Either user picked "Local:" or "Remote:". If remote, we need to download.
###############################################################################
if [[ -z "$ISO_URL" ]]; then
    # Means user picked a local ISO
    echo "'${isoName}' is a local ISO. No download needed." >&2
else
    # We have a remote link; check if isoName is already in localIsoStore
    if ! pvesm list "$localIsoStore" 2>/dev/null | grep -q "$isoName"; then
        declare isoVolId="${localIsoStore}:iso/${isoName}"
        declare isoPath
        isoPath=$(pvesm path "$isoVolId" 2>/dev/null)
        if [[ -z "$isoPath" ]]; then
            echo >&2 "Error: Could not determine path for volume ID '$isoVolId'."
            echo >&2 "Make sure '$localIsoStore' is configured for ISO images."
            exit 1
        fi
        echo >&2 "Downloading '$isoName' from '$ISO_URL' to '$isoPath'..."
        curl -L "$ISO_URL" -o "$isoPath" || {
            echo >&2 "Error: Failed to download '$ISO_URL'."
            exit 1
        }
    else
        echo >&2 "'$isoName' is already present in storage '$localIsoStore'. Skipping download."
    fi
fi

###############################################################################
# Convert memory from GiB to MiB, create the VM
###############################################################################
MEMORY_MB=$(( MEMORY_GIB * 1024 ))

qm create "$VM_ID" --name "$VM_NAME" --memory "$MEMORY_MB" --cores "$CPU_CORES"

# BIOS or UEFI
if [[ "$BIOS_TYPE" == "uefi" ]]; then
    qm set "$VM_ID" --bios ovmf --efidisk0 "$VM_STORAGE":0,format=raw,size=4M
else
    qm set "$VM_ID" --bios seabios
fi

# Infer OS type
if [[ -z "$isoName" ]]; then
    OS_TYPE="linux"
else
    isoLower="${isoName,,}"
    if [[ "$isoLower" == *"win"* ]]; then
        OS_TYPE="windows"
    else
        OS_TYPE="linux"
    fi
fi

# Create the main disk
VOL_ID="$(disk_volume_id "$VM_STORAGE" "$DISK_GIB")"
qm set "$VM_ID" --scsihw virtio-scsi-pci --scsi0 "${VOL_ID},discard=on,ssd=1,cache=none"

# If Windows, add TPM & secondary virtio
if [[ "$OS_TYPE" == "windows" ]]; then
    qm set "$VM_ID" --tpmstate0 "$VM_STORAGE":1,size=4,version=v2.0
    local virtioVolId
    virtioVolId="$(disk_volume_id "$VM_STORAGE" "4")"
    qm set "$VM_ID" --virtio0 "${virtioVolId},cache=none"
fi

# CPU model
if [[ "$CPU_MODEL" == "host" ]]; then
    qm set "$VM_ID" --cpu cputype=host --numa 1
else
    qm set "$VM_ID" --numa 1
fi

# Balloon/hotplug
qm set "$VM_ID" --balloon "$MEMORY_MB" --hotplug memory

# Network
qm set "$VM_ID" --net0 "virtio,bridge=$BRIDGE_NAME,firewall=0"

# Attach ISO if we have it (localIsoStore + isoName)
if [[ -n "$isoName" ]]; then
    qm set "$VM_ID" --cdrom "$localIsoStore:iso/$isoName"
fi

# QEMU guest agent
qm set "$VM_ID" --agent enabled=1,fstrim_cloned_disks=1

qm start "$VM_ID"
echo >&2 "VM '$VM_NAME' (ID: $VM_ID) created and started."
