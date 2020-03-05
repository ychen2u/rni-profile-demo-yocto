set -xe

IMG_OR_MP=$1
DST="./diskmnt"

mkdir -p $DST

mount_img() (
  img="$1"
  dst="$2"
  dev="$(sudo losetup --show -f -P "$img")"
  echo "$dev"
  for part in "$dev"; do
    if [ "$part" = "${dev}p*" ]; then
      part="${dev}"
    fi
    sudo mount "$part" "$dst"
  done
)

mount_img $IMG_OR_MP $DST

cp -r $DST/* .

sudo umount $DST
rm -r $DST

