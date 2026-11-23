SETUP_VOLUME_ID=${1:?Pass DataVolumeId from prepare-console-ec2.sh}
SETUP_SERIAL=${SETUP_VOLUME_ID//-/}
mapfile -t SETUP_DEVICES < <(lsblk -dnpo PATH,SERIAL | awk -v serial="$SETUP_SERIAL" '$2 == serial {print $1}')
[ "${#SETUP_DEVICES[@]}" -eq 1 ] || { echo 'Cannot identify the Console data volume by its EBS volume ID.'; exit 1; }
SETUP_DEVICE=${SETUP_DEVICES[0]}
[ "$(lsblk -nro TYPE "$SETUP_DEVICE" | wc -l)" -eq 1 ] || { echo 'The data volume has partitions. Check it before installing.'; exit 1; }
SETUP_BLKID_STATUS=0
SETUP_FSTYPE=$(sudo blkid -p -s TYPE -o value "$SETUP_DEVICE") || SETUP_BLKID_STATUS=$?
[ "$SETUP_BLKID_STATUS" -eq 0 ] || [ "$SETUP_BLKID_STATUS" -eq 2 ] || exit 1
if [ -z "$SETUP_FSTYPE" ]; then
  SETUP_SIGNATURES=$(sudo wipefs --no-act --noheadings --output TYPE "$SETUP_DEVICE")
  [ -z "$SETUP_SIGNATURES" ] || { echo 'The data volume has an existing disk signature.'; exit 1; }
  [ -z "$(lsblk -nro MOUNTPOINTS "$SETUP_DEVICE" | tr -d '[:space:]')" ] || exit 1
  sudo mkfs.xfs "$SETUP_DEVICE"
else
  [ "$SETUP_FSTYPE" = xfs ] || { echo 'The data volume uses a filesystem other than XFS.'; exit 1; }
fi
SETUP_UUID=$(sudo blkid -s UUID -o value "$SETUP_DEVICE")
[ -n "$SETUP_UUID" ]
sudo mkdir -p /data
if mountpoint -q /data; then
  [ "$(findmnt -n -o UUID --target /data)" = "$SETUP_UUID" ] || exit 1
else
  [ -z "$(sudo ls -A /data)" ] || { echo '/data contains files. Check the mount before installing.'; exit 1; }
fi
SETUP_FSTAB_LINE="UUID=$SETUP_UUID /data xfs defaults,nofail 0 2"
if grep -Eq '^[^#]+[[:space:]]/data[[:space:]]' /etc/fstab; then
  grep -Fxq "$SETUP_FSTAB_LINE" /etc/fstab || { echo '/etc/fstab already contains a different entry for /data.'; exit 1; }
else
  sudo cp -a /etc/fstab "/etc/fstab.automq-backup-$(date +%s)"
  printf '%s\n' "$SETUP_FSTAB_LINE" | sudo tee -a /etc/fstab >/dev/null
fi
sudo systemctl daemon-reload
mountpoint -q /data || sudo mount /data
[ "$(findmnt -n -o UUID --target /data)" = "$SETUP_UUID" ]
sudo install -d -m 0700 /data/automq-console
