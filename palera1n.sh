#!/usr/bin/env bash

mkdir -p logs

{

set -e

# =========
# Variables
# =========
ipsw="" # IF YOU WERE TOLD TO PUT A CUSTOM IPSW URL, PUT IT HERE. YOU CAN FIND THEM ON https://appledb.dev
version="1.0.0"
os=$(uname)
dir="$(pwd)/binaries/$os"
commit=$(git rev-parse --short HEAD)
if [[ "$@" == *"--debug"* ]]; then
    out=/dev/stdout
else
    out=/dev/null
fi

# =========
# Functions
# =========
step() {
    for i in $(seq "$1" -1 1); do
        printf '\r\e[1;36m%s (%d) ' "$2" "$i"
        sleep 1
    done
    printf '\r\e[0m%s (0)\n' "$2"
}

_wait() {
    if [ "$1" = 'normal' ]; then
        if [ "$os" = 'Darwin' ]; then
            if ! (system_profiler SPUSBDataType 2> /dev/null | grep 'Manufacturer: Apple Inc.' >> /dev/null); then
                echo "[*] Waiting for device in normal mode"
            fi

            while ! (system_profiler SPUSBDataType 2> /dev/null | grep 'Manufacturer: Apple Inc.' >> /dev/null); do
                sleep 1
            done
        else
            if ! (lsusb 2> /dev/null | grep ' Apple, Inc.' >> /dev/null); then
                echo "[*] Waiting for device in normal mode"
            fi

            while ! (lsusb 2> /dev/null | grep ' Apple, Inc.' >> /dev/null); do
                sleep 1
            done
        fi
    elif [ "$1" = 'recovery' ]; then
        if [ "$os" = 'Darwin' ]; then
            if ! (system_profiler SPUSBDataType 2> /dev/null | grep ' Apple Mobile Device (Recovery Mode):' >> /dev/null); then
                echo "[*] Waiting for device to reconnect in recovery mode"
            fi

            while ! (system_profiler SPUSBDataType 2> /dev/null | grep ' Apple Mobile Device (Recovery Mode):' >> /dev/null); do
                sleep 1
            done
        else
            if ! (lsusb 2> /dev/null | grep 'Recovery Mode' >> /dev/null); then
                echo "[*] Waiting for device to reconnect in recovery mode"
            fi

            while ! (lsusb 2> /dev/null | grep 'Recovery Mode' >> /dev/null); do
                sleep 1
            done
        fi
        if [[ ! $1 == *"--tweaks"* ]]; then
            "$dir"/irecovery -c "setenv auto-boot true"
            "$dir"/irecovery -c "saveenv"
        fi

    fi
}

_check_dfu() {
    if [ "$os" = 'Darwin' ]; then
        if ! (system_profiler SPUSBDataType 2> /dev/null | grep ' Apple Mobile Device (DFU Mode):' >> /dev/null); then
            echo "[-] Device didn't go in DFU mode, please rerun the script and try again"
            exit
        fi
    else
        if ! (lsusb 2> /dev/null | grep 'DFU Mode' >> /dev/null); then
            echo "[-] Device didn't go in DFU mode, please rerun the script and try again"
            exit
        fi
    fi
}

_info() {
    if [ "$1" = 'recovery' ]; then
        echo $("$dir"/irecovery -q | grep "$2" | sed "s/$2: //")
    elif [ "$1" = 'normal' ]; then
        echo $("$dir"/ideviceinfo | grep "$2: " | sed "s/$2: //")
    fi
}

_pwn() {
    pwnd=$(_info recovery PWND)
    if [ "$pwnd" = "" ]; then
        echo "[*] Pwning device"
        "$dir"/gaster pwn > "$out"
        sleep 2
        #"$dir"/gaster reset > "$out"
        #sleep 1
    fi
}

_dfuhelper() {
    echo "[*] Press any key when ready for DFU mode"
    read -n 1 -s
    step 3 "Get ready"
    step 4 "Hold volume down + side button" &
    sleep 3
    "$dir"/irecovery -c "reset"
    step 1 "Keep holding"
    step 10 'Release side button, but keep holding volume down'
    sleep 1
    
    _check_dfu
    echo "[*] Device entered DFU!"
}

_kill_if_running() {
    if (pgrep -u root -xf "$1" &> /dev/null > /dev/null); then
        # yes, it's running as root. kill it
        sudo killall $1
    else
        if (pgrep -x "$1" &> /dev/null > /dev/null); then
            killall $1
        fi
    fi
}

_exit_handler() {
    if [ "$os" = 'Darwin' ]; then
        if [ ! "$1" = '--dfu' ]; then
            defaults write -g ignore-devices -bool false
            defaults write com.apple.AMPDevicesAgent dontAutomaticallySyncIPods -bool false
            killall Finder
        fi
    fi
    [ $? -eq 0 ] && exit
    echo "[-] An error occurred"

    cd logs
    for file in *.log; do
        mv "$file" FAIL_${file}
    done
    cd ..

    if [[ "$@" == *"--debug"* ]]; then
        echo "[*] A failure log has been made. If you're going to make a GitHub issue, please attatch the latest log."
    else
        echo "[*] A failure log has been made, but you aren't running with --debug. DO NOT send this in a GitHub issue."
    fi
}
trap _exit_handler EXIT

# ===========
# Fixes
# ===========

# Prevent Finder from complaning
if [ "$os" = 'Darwin' ]; then
    defaults write -g ignore-devices -bool true
    defaults write com.apple.AMPDevicesAgent dontAutomaticallySyncIPods -bool true
    killall Finder
fi

# ===========
# Subcommands
# ===========

if [ "$1" = 'clean' ]; then
    rm -rf boot* work
    rm -rf tweaksinstalled
    echo "[*] Removed the created boot files"
    exit
fi

# ============
# Dependencies
# ============

# Download gaster
if [ ! -e "$dir"/gaster ]; then
    curl -sLO https://nightly.link/verygenericname/gaster/workflows/makefile/main/gaster-"$os".zip
    unzip gaster-"$os".zip > "$out"
    mv gaster "$dir"/
    rm -rf gaster gaster-"$os".zip
fi

# Check for pyimg4
if ! python3 -c 'import pkgutil; exit(not pkgutil.find_loader("pyimg4"))'; then
    echo '[-] pyimg4 not installed. Press any key to install it, or press ctrl + c to cancel'
    read -n 1 -s
    python3 -m pip install pyimg4 > "$out"
fi

# ============
# Prep
# ============

# Update submodules
git submodule update --init --recursive > "$out"

# Re-create work dir if it exists, else, make it
if [ -e work ]; then
    rm -rf work
    mkdir work
else
    mkdir work
fi

chmod +x "$dir"/*
#if [ "$os" = 'Darwin' ]; then
#    xattr -d com.apple.quarantine "$dir"/*
#fi

# ============
# Start
# ============

echo "palera1n | Version $version-$commit"
echo "Written by Nebula and Mineek | Some code and ramdisk from Nathan | Loader app by Amy"
echo ""

if [ "$1" = '--tweaks' ] && [ ! -e tweaksinstalled ]; then
    echo "!!! WARNING WARNING WARNING !!!"
    echo "This flag will add tweak support BUT WILL BE TETHERED."
    echo "THIS ALSO MEANS THAT YOU'LL NEED A PC EVERY TIME TO BOOT."
    echo "THIS ONLY WORKS ON 15.0-15.3.1"
    echo "DO NOT GET ANGRY AT US IF UR DEVICE IS BORKED, IT'S YOUR OWN FAULT AND WE WARNED YOU"
    echo "DO YOU UNDERSTAND? TYPE 'Yes, do as I say.' TO CONTINUE"
    read -r answer
    if [ "$answer" = 'Yes, do as I say.' ]; then
        echo "Are you REALLY sure? WE WARNED U!"
        echo "Type 'YES, I'm really sure' to continue"
        read -r answer
        if [ "$answer" = 'YES, I'"'"'m really sure' ]; then
            echo "[*] Enabling tweaks"
            tweaks=1
        else
            echo "[*] Disabling tweaks"
            tweaks=0
        fi
    else
        echo "[*] Disabling tweaks"
        tweaks=0
    fi
fi

# Get device's iOS version from ideviceinfo if in normal mode
if [ "$1" = '--dfu' ] || [ "$1" = '--tweaks' ]; then
    if [ -z "$2" ]; then
        echo "[-] When using --dfu, please pass the version you're device is on"
        exit
    else
        version=$2
    fi
else
    _wait normal
    version=$(_info normal ProductVersion)
    arch=$(_info normal CPUArchitecture)
    if [ "$arch" = "arm64e" ]; then
        echo "[-] palera1n doesn't, and never will, work on non-checkm8 devices"
        exit
    fi
    echo "Hello, $(_info normal ProductType) on $version!"
fi

# Put device into recovery mode, and set auto-boot to true
if [ ! "$1" = '--dfu' ] && [ ! "$1" = '--tweaks' ]; then
    echo "[*] Switching device into recovery mode..."
    "$dir"/ideviceenterrecovery $(_info normal UniqueDeviceID) > "$out"
    _wait recovery
fi

# Grab more info
echo "[*] Getting device info..."
cpid=$(_info recovery CPID)
model=$(_info recovery MODEL)
deviceid=$(_info recovery PRODUCT)
if [ ! "$ipsw" = "" ]; then
    ipswurl=$ipsw
else
    ipswurl=$(curl -sL "https://api.ipsw.me/v4/device/$deviceid?type=ipsw" | "$dir"/jq '.firmwares | .[] | select(.version=="'"$version"'") | .url' --raw-output)
fi

# Have the user put the device into DFU
if [ ! "$1" = '--dfu' ] && [ ! "$1" = '--tweaks' ]; then
    _dfuhelper
fi
sleep 2

# if the user specified --restorerootfs, execute irecovery -n
if [ "$1" = '--restorerootfs' ]; then
    echo "[*] Restoring rootfs..."
    "$dir"/irecovery -n > "$out"
    sleep 2
    echo "[*] Done, your device will boot into iOS now."
    # clean the boot files bcs we don't need them anymore
    rm -rf boot*
    rm -rf work
    rm -rf tweaksinstalled
    exit
fi

# ============
# Ramdisk
# ============

# Dump blobs, and install pogo if needed
if [ ! -f blobs/"$deviceid"-"$version".shsh2 ]; then
    mkdir -p blobs
    cd ramdisk

    chmod +x sshrd.sh
    echo "[*] Creating ramdisk"
    ./sshrd.sh 14.8 &> "$out" > "$out"

    echo "[*] Booting ramdisk"
    ./sshrd.sh boot > "$out"
    cd ..
    # if known hosts file exists, remove it
    if [ -f ~/.ssh/known_hosts ]; then
        rm ~/.ssh/known_hosts
    fi

    # Execute the commands once the rd is booted
    if [ "$os" = 'Linux' ]; then
        sudo "$dir"/iproxy 2222 22 &> "$out" >> "$out" &
    else
        "$dir"/iproxy 2222 22 &> "$out" >> "$out" &
    fi

    if ! ("$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "echo connected" &> /dev/null > "$out"); then
        echo "[*] Waiting for the ramdisk to finish booting"
    fi

    while ! ("$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "echo connected" &> /dev/null > "$out"); do
        sleep 1
    done

    echo "[*] Dumping blobs and installing Pogo"
    sleep 1
    "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "cat /dev/rdisk1" | dd of=dump.raw bs=256 count=$((0x4000)) > "$out" 
    "$dir"/img4tool --convert -s blobs/"$deviceid"-"$version".shsh2 dump.raw > "$out"
    rm dump.raw
    if [[ ! "$@" == *"--no-install"* ]]; then
        #"$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/mount_apfs /dev/disk0s1s1 /mnt1" > "$out"
        #sleep 1
        #"$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/mount_apfs -R /dev/disk0s1s6 /mnt6" > "$out"
        #sleep 1
        #"$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/mount_apfs -R /dev/disk0s1s3 /mnt7" > "$out"
        #sleep 1
        #"$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/libexec/seputil --gigalocker-init" > "$out"
        #sleep 1
        #active=$("$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/bin/cat /mnt6/active" 2> /dev/null)
        #"$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/libexec/seputil --load /mnt6/$active/usr/standalone/firmware/sep-firmware.img4" > "$out"
        #sleep 1
        #"$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/mount_apfs /dev/disk0s1s2 /mnt2" > "$out"
        #sleep 1
        "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/bin/mount_filesystems" > "$out"
        sleep 1
        tipsdir=$("$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/bin/find /mnt2/containers/Bundle/Application/ -name 'Tips.app'" 2> /dev/null)
        "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/bin/cp -rf /usr/local/bin/loader.app/* $tipsdir" > "$out"
        "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/sbin/chown 33 $tipsdir/Tips" > "$out"
        "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/bin/chmod 755 $tipsdir/Tips $tipsdir/PogoHelper" > "$out"
        "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/sbin/chown 0 $tipsdir/PogoHelper" > "$out"
    fi
    if [[ $1 == *"--tweaks"* ]]; then
        # execute nvram boot-args="-v keepsyms=1 debug=0x2014e launchd_unsecure_cache=1 launchd_missing_exec_no_panic=1 amfi=0xff amfi_allow_any_signature=1 amfi_get_out_of_my_way=1 amfi_allow_research=1 amfi_unrestrict_task_for_pid=1 amfi_unrestricted_local_signing=1 cs_enforcement_disable=1 pmap_cs_allow_modified_code_pages=1 pmap_cs_enforce_coretrust=0 pmap_cs_unrestrict_pmap_cs_disable=1 -unsafe_kernel_text dtrace_dof_mode=1 panic-wait-forever=1 -panic_notify cs_debug=1 PE_i_can_has_debugger=1 wdt=-1"
        "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/sbin/nvram boot-args=\"-v keepsyms=1 debug=0x2014e launchd_unsecure_cache=1 launchd_missing_exec_no_panic=1 amfi=0xff amfi_allow_any_signature=1 amfi_get_out_of_my_way=1 amfi_allow_research=1 amfi_unrestrict_task_for_pid=1 amfi_unrestricted_local_signing=1 cs_enforcement_disable=1 pmap_cs_allow_modified_code_pages=1 pmap_cs_enforce_coretrust=0 pmap_cs_unrestrict_pmap_cs_disable=1 -unsafe_kernel_text dtrace_dof_mode=1 panic-wait-forever=1 -panic_notify cs_debug=1 PE_i_can_has_debugger=1 wdt=-1\"" > "$out"
        # execute nvram allow-root-hash-mismatch=1
        "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/sbin/nvram allow-root-hash-mismatch=1" > "$out"
        # execute nvram root-live-fs=1
        "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/sbin/nvram root-live-fs=1" > "$out"
        # execute nvram auto-boot=false
        "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/usr/sbin/nvram auto-boot=false" > "$out"
    fi
    sleep 2
    "$dir"/sshpass -p 'alpine' ssh -o StrictHostKeyChecking=no -p2222 root@localhost "/sbin/reboot" > "$out"
    sleep 1
    _kill_if_running iproxy
    _wait normal
    sleep 2

    # Switch into recovery, and set auto-boot to true
    if [ ! "$1" = "--tweaks" ]; then
        echo "[*] Switching device into recovery mode..."
        "$dir"/ideviceenterrecovery $(_info normal UniqueDeviceID) > "$out"
        _wait recovery
        # Have the user put the device into DFU
    fi
    sleep 10
    _dfuhelper
    sleep 2
fi

# ============
# Boot create
# ============

# Actually create the boot files
if [ ! -e boot-"$deviceid" ]; then
    _pwn

    # if tweaks, set ipswurl to a custom one
    if [ "$1" = "--tweaks" ]; then
        read -p "[*] Enter the URL of the OTA ZIP of 15.1b3 of your device: " ipswurl
    fi

    # Downloading files, and decrypting iBSS/iBEC
    mkdir boot-"$deviceid"

    echo "[*] Converting blob"
    "$dir"/img4tool -e -s $(pwd)/blobs/"$deviceid"-"$version".shsh2 -m work/IM4M > "$out"
    cd work

    echo "[*] Downloading BuildManifest"
    "$dir"/pzb -g AssetData/boot/BuildManifest.plist "$ipswurl" > "$out"

    echo "[*] Downloading and decrypting iBSS"
    "$dir"/pzb -g AssetData/boot/"$(awk "/""$cpid""/{x=1}x&&/iBSS[.]/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1 | sed 's/RELEASE/DEVELOPMENT/')" "$ipswurl" > "$out"
    "$dir"/gaster decrypt "$(awk "/""$cpid""/{x=1}x&&/iBSS[.]/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1 | sed 's/Firmware[/]dfu[/]//' | sed 's/RELEASE/DEVELOPMENT/')" iBSS.dec > "$out"

    echo "[*] Downloading and decrypting iBEC"
    # download ibec and replace RELEASE with DEVELOPMENT
    "$dir"/pzb -g AssetData/boot/"$(awk "/""$cpid""/{x=1}x&&/iBEC[.]/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1 | sed 's/RELEASE/DEVELOPMENT/')" "$ipswurl" > "$out"
    "$dir"/gaster decrypt "$(awk "/""$cpid""/{x=1}x&&/iBEC[.]/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1 | sed 's/Firmware[/]dfu[/]//' | sed 's/RELEASE/DEVELOPMENT/')" iBEC.dec > "$out"

    echo "[*] Downloading DeviceTree"
    "$dir"/pzb -g AssetData/boot/Firmware/all_flash/DeviceTree."$model".im4p "$ipswurl" > "$out"

    echo "[*] Downloading trustcache"
    if [ "$os" = 'Darwin' ]; then
       "$dir"/pzb -g AssetData/boot/"$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."StaticTrustCache"."Info"."Path" xml1 -o - BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1 | head -1)" "$ipswurl" > "$out"
    else
       "$dir"/pzb -g AssetData/boot/"$("$dir"/PlistBuddy BuildManifest.plist -c "Print BuildIdentities:0:Manifest:StaticTrustCache:Info:Path" | sed 's/"//g')" "$ipswurl" > "$out"
    fi

    echo "[*] Downloading kernelcache"
    if [[ $1 == *"--tweaks"* ]]; then
        "$dir"/pzb -g AssetData/boot/"$(awk "/""$cpid""/{x=1}x&&/kernelcache.release/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1 | sed 's/release/development/')" "$ipswurl" > "$out"
    else
        "$dir"/pzb -g "$(awk "/""$cpid""/{x=1}x&&/kernelcache.release/{print;exit}" BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1)" "$ipswurl" > "$out"
    fi

    echo "[*] Patching and signing iBSS/iBEC"
    "$dir"/iBoot64Patcher iBSS.dec iBSS.patched > "$out"
    if [[ $1 == *"--tweaks"* ]]; then
        "$dir"/iBoot64Patcher iBEC.dec iBEC.patched > "$out"
    else
        "$dir"/iBoot64Patcher iBEC.dec iBEC.patched -b '-v keepsyms=1 debug=0x2014e panic-wait-forever=1 wdt=-1' > "$out"
    fi
    cd ..
    "$dir"/img4 -i work/iBSS.patched -o boot-"$deviceid"/iBSS.img4 -M work/IM4M -A -T ibss > "$out"
    "$dir"/img4 -i work/iBEC.patched -o boot-"$deviceid"/iBEC.img4 -M work/IM4M -A -T ibec > "$out"

    echo "[*] Patching and signing kernelcache"
    if [[ "$deviceid" == "iPhone8"* ]] || [[ "$deviceid" == "iPad6"* ]] && [[ ! $1 == *"--tweaks"* ]]; then
        python3 -m pyimg4 im4p extract -i work/"$(awk "/""$model""/{x=1}x&&/kernelcache.release/{print;exit}" work/BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1)" -o work/kcache.raw --extra work/kpp.bin > "$out"
    elif [[ ! $1 == *"--tweaks"* ]]; then
        python3 -m pyimg4 im4p extract -i work/"$(awk "/""$model""/{x=1}x&&/kernelcache.release/{print;exit}" work/BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1)" -o work/kcache.raw > "$out"
    fi

    if [[ $1 == *"--tweaks"* ]]; then
        modelwithoutap=$(echo "$model" | sed 's/ap//')
        bpatchfile=$(find patches -name "$modelwithoutap".bpatch)
        "$dir"/img4 -i work/kernelcache.development.* -o boot-"$deviceid"/kernelcache.img4 -M work/IM4M -T rkrn -P "$bpatchfile" `if [ "$os" = 'Linux' ]; then echo "-J"; fi` > "$out"
    else
        "$dir"/Kernel64Patcher work/kcache.raw work/kcache.patched -a -o > "$out"
    fi

    if [[ "$deviceid" == *'iPhone8'* ]] || [[ "$deviceid" == *'iPad6'* ]] && [[ ! $1 == *"--tweaks"* ]]; then
        python3 -m pyimg4 im4p create -i work/kcache.patched -o work/krnlboot.im4p --extra work/kpp.bin -f rkrn --lzss > "$out"
    elif [[ ! $1 == *"--tweaks"* ]]; then
        python3 -m pyimg4 im4p create -i work/kcache.patched -o work/krnlboot.im4p -f rkrn --lzss > "$out"
    fi

    if [[ ! $1 == *"--tweaks"* ]]; then
        python3 -m pyimg4 img4 create -p work/krnlboot.im4p -o boot-"$deviceid"/kernelcache.img4 -m work/IM4M > "$out"
    fi

    echo "[*] Signing DeviceTree"
    "$dir"/img4 -i work/"$(awk "/""$model""/{x=1}x&&/DeviceTree[.]/{print;exit}" work/BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1 | sed 's/Firmware[/]all_flash[/]//')" -o boot-"$deviceid"/devicetree.img4 -M work/IM4M -T rdtr > "$out"

    echo "[*] Patching and signing trustcache"
    if [ "$os" = 'Darwin' ]; then
        "$dir"/img4 -i work/"$(/usr/bin/plutil -extract "BuildIdentities".0."Manifest"."StaticTrustCache"."Info"."Path" xml1 -o - work/BuildManifest.plist | grep '<string>' | cut -d\> -f2 | cut -d\< -f1 | head -1 | sed 's/Firmware\///')" -o boot-"$deviceid"/trustcache.img4 -M work/IM4M -T rtsc > "$out"
    else
        "$dir"/img4 -i work/"$("$dir"/PlistBuddy work/BuildManifest.plist -c "Print BuildIdentities:0:Manifest:StaticTrustCache:Info:Path" | sed 's/"//g'| sed 's/Firmware\///')" -o boot-"$deviceid"/trustcache.img4 -M work/IM4M -T rtsc > "$out"
    fi

    "$dir"/img4 -i other/bootlogo.im4p -o boot-"$deviceid"/bootlogo.img4 -M work/IM4M -A -T rlgo > "$out"
fi

# ============
# Boot device
# ============

sleep 2
_pwn
echo "[*] Booting device"
"$dir"/irecovery -f boot-"$deviceid"/iBSS.img4
sleep 1
"$dir"/irecovery -f boot-"$deviceid"/iBSS.img4
sleep 2
"$dir"/irecovery -f boot-"$deviceid"/iBEC.img4
sleep 1
if [[ "$cpid" == *"0x80"* ]]; then
    "$dir"/irecovery -c "go"
    sleep 2
fi
"$dir"/irecovery -f boot-"$deviceid"/bootlogo.img4
"$dir"/irecovery -c "setpicture 0x1"
"$dir"/irecovery -f boot-"$deviceid"/devicetree.img4
"$dir"/irecovery -c "devicetree"
"$dir"/irecovery -f boot-"$deviceid"/trustcache.img4
"$dir"/irecovery -c "firmware"
"$dir"/irecovery -f boot-"$deviceid"/kernelcache.img4
sleep 2
"$dir"/irecovery -c "bootx"

if [ "$os" = 'Darwin' ]; then
    if [ ! "$1" = '--dfu' ]; then
        defaults write -g ignore-devices -bool false
        defaults write com.apple.AMPDevicesAgent dontAutomaticallySyncIPods -bool false
        killall Finder
    fi
fi

if [ $1 = '--tweaks' ] && [ ! -f "tweaksinstalled" ]; then
    echo "[*] Tweaks enabled, running postinstall."
    echo "[!] Please install OpenSSH, curl, and wget from Sileo (repo is mineek.github.io/repo). Then, press any key to continue"
    read -n 1 -s
    echo "[*] Installing tweak support, please follow the instructions 100% or unexpected errors may occur"
    "$dir"/iproxy 2222 22 &
    if [ -f ~/.ssh/known_hosts ]; then
        rm ~/.ssh/known_hosts
    fi
    echo "[!] If asked for a password, enter 'alpine'."
    # ssh into device and copy over the preptweaks.sh script from the binaries folder
    scp -P2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=QUIET binaries/preptweaks.sh mobile@localhost:~/preptweaks.sh
    # run the preptweaks.sh script as root
    ssh -p2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=QUIET mobile@localhost "echo 'alpine' | sudo -S sh ~/preptweaks.sh"
    # now tell the user to install preferenceloader from bigboss repo and newterm2
    echo "[*] Please install PreferenceLoader from BigBoss repo and NewTerm 2. Then, press any key to continue"
    read -n 1 -s
    # now run sbreload
    "$dir"/sshpass -p alpine ssh -o StrictHostKeyChecking=no root@localhost -p 2222 "sbreload"
    echo "[*] Tweak support installed, you can freely use Sileo now."
    touch tweaksinstalled 
fi

if [ -f "tweaksinstalled" ]; then
    # if known hosts file exists, delete it
    if [ -f ~/.ssh/known_hosts ]; then
        rm ~/.ssh/known_hosts
    fi

    # run postboot.sh script
    if [ -f binaries/postboot.sh ]; then
        echo "[*] Running postboot"
        "$dir"/iproxy 2222 22 &
        scp -P2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=QUIET binaries/postboot.sh mobile@localhost:~/postboot.sh
        ssh -p2222 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=QUIET mobile@localhost "echo 'alpine' | sudo -S sh ~/postboot.sh"
    fi

    # if known hosts file exists, delete it
    if [ -f ~/.ssh/known_hosts ]; then
        rm ~/.ssh/known_hosts
    fi

    _kill_if_running iproxy
fi

cd logs
for file in *.log; do
    mv "$file" SUCCESS_${file}
done
cd ..

rm -rf work rdwork
echo ""
echo "Done!"
echo "The device should now boot to iOS"
echo "If you already have ran palera1n, click Do All in the tools section of Pogo"
echo "If not, Pogo should be installed to Tips"

} | tee logs/"$(date +%T)"-"$(date +%F)"-"$(uname)"-"$(uname -r)".log
