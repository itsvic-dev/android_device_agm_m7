#!/vendor/bin/sh
# The modem writes its NVRAM at runtime; it works on a copy, never on the stock partitions.
d=/data/vendor/ccci-fs
[ -d $d/nvdata/md/NVRAM ] && exit 0
mkdir -p $d/nvdata $d/protect_f $d/protect_s
cp -R /mnt/vendor/nvdata/md /mnt/vendor/nvdata/md_cmn $d/nvdata/
cp -R /mnt/vendor/protect_f/md $d/protect_f/
cp -R /mnt/vendor/protect_s/md $d/protect_s/
