#!/bin/sh

partition() {
  echo $(fdisk -l /dev/sda | grep "$1" | awk '{print $1;}')
}

aur() {
  git clone "https://aur.archlinux.org/$1.git"
  cd $1
  makepkg -sir
  cd ..
}

linux=$(partition "Linux filesystem")
efi=$(partition "EFI System")

prepare() {
  echo "[PREPARE]"

  timedatectl set-ntp true
  mkfs.ext4 $linux -f

  mount $linux /mnt
  mkdir /mnt/boot
  mount $efi /mnt/boot

  read -p "Enter amd or intel for microcode: " microcode

  packages=(
    $microcode-ucode
    base
    base-devel
    bash-completion
    ccache
    cups
    curl
    dart
    discord
    dolphin
    efibootmgr
    firefox
    git
    kdeconnect
    kio-gdrive
    konsole
    linux
    linux-firmware 
    lz4
    man
    neofetch
    networkmanager
    openrct2
    packagekit-qt5
    plasma-meta
    print-manager
    sudo
    ttf-fira-code
    vim
  )

  pacstrap /mnt $(printf "%s " "${packages[@]}")

  genfstab -U /mnt >> /mnt/etc/fstab

  cp $0 /mnt/root/

  arch-chroot /mnt /root/birch.sh chroot $microcode

  umount -R /mnt
  echo "Done!"
}

configure() {
  echo "[CHROOT]"

  # Configure time zone.
  ln -sf /usr/share/zoneinfo/America/New_York /etc/localtime
  timedatectl set-local-rtc 1

  # Configure locale.
  locale="en_US.UTF-8"
  line="$locale UTF-8"
  sed -i "/^#$line/ c$line" /etc/locale.gen
  locale-gen
  echo "LANG=$locale" > /etc/locale.conf

  # Configure hostname.
  read -p "Enter hostname: " hostname
  echo $hostname > /etc/hostname
  echo "127.0.0.1 localhost" >> /etc/hosts
  echo "::1 localhost" >> /etc/hosts
  echo "127.0.1.1 $hostname.localdomain $hostname" >> /etc/hosts

  # Create user.
  read -p "Enter username: " username
  useradd -m -G wheel $username
  passwd $username

  # Configure sudo.
  line="%wheel ALL=(ALL) ALL"
  sed -i "/^# $line/ c$line" /etc/sudoers

  # Enable services.
  systemctl enable sddm.service
  systemctl enable cups.service
  systemctl enable NetworkManager.service

  # Install Steam.
  echo "[multilib]" >> /etc/pacman.conf
  echo "Include = /etc/pacman.d/mirrorlist" >> /etc/pacman.conf
  pacman -Sy steam

  # Configure user.
  cp /root/birch.sh /home/$username/
  sudo -u $username /home/$username/birch.sh user

  # Configure plymouth.
  plymouth-set-default-theme BGRT
  read -p "Provide graphics module: " module
  sed -i "/^MODULES=()/ cMODULES=($module)" /etc/mkinitcpio.conf
  sed 's/\(udev autodetect\)/udev plymouth autodetect/' /etc/mkinitcpio.conf

  # LZ4 compression.
  line="COMPRESSION=\"lz4\""
  sed -i "/^#$line/ c$line" /etc/mkinitcpio.conf

  mkinitcpio -P

  # Configure EFI.
  efi $1

  rm /root/birch.sh
  exit 0
}

efi() {
  efi_num=$(echo $efi | sed 's/[^0-9]*//g')
  efi_disk=$(echo $efi | sed 's/[0-9]*//g')
  partuuid=$(blkid | grep $linux | sed 's/\(.\+PARTUUID="\)\|\("\)//g')
  args=(
    "root=PARTUUID=$partuuid"
    "rw"
    "initrd=\\\\"$1"-ucode.img"
    "initrd=\\\\initramfs-linux.img"
    "quiet"
    "splash"
    "rd.udev.log_priority=3"
    "vt.global_cursor_default=0" 
  )
  unicode=$(printf "%s " "${args[@]}" | xargs)
  echo $unicode
  efibootmgr \
    --disk $efi_disk \
    --part $efi_num \
    --create \
    --label "Arch Linux" \
    --loader /vmlinuz-linux \
    --unicode "$unicode" \
    --verbose

  read -p "Are you installing on a mac? " mac
  if [ "$mac" = "y" ]; then
    cd
    git clone https://github.com/0xbb/gpu-switch
    cd gpu-switch
    ./gpu-switch -i
    cd ..
    rm -r gpu-switch
    
    mkdir -p /boot/EFI/spoof
    cd /boot/EFI/spoof
    curl https://github.com/0xbb/apple_set_os.efi/releases/download/v1/apple_set_os.efi > apple_set_os.efi
    efibootmgr \
      --disk $efi_disk \
      --part $efi_num \
      --create \
      --label "Spoof" \
      --loader /EFI/spoof/apple_set_os.efi \
      --verbose
  fi
}

user() {
  cd
  rm .bashrc .bash_profile
  git clone https://github.com/brianji/dotdart
  cd dotdart
  pub get
  dart run

  # Install AUR packages.
  cd
  mkdir build
  cd build
  aur google-chrome
  aur minecraft-launcher
  aur plymouth
  aur visual-studio-code-bin
  
  rm ../birch.sh
}

if [ "$1" = "chroot" ]; then
  configure $2
elif [ "$1" = "user" ]; then
  user
elif [ "$1" = "efi" ]; then
  efi $2
else
  prepare
fi
