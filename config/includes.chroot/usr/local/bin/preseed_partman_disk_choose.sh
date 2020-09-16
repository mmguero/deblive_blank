#!/bin/sh

DISK_LIST=$(parted_devices | egrep "^($(find /sys/block -mindepth 1 -maxdepth 1 -type l \( -name '[hs]d*' -o -name 'nvme*' \) -exec ls -l '{}' ';' | grep -v "usb" | sed 's@^.*\([hs]d[a-z]\+\|nvme[0-9]\+\).*$@/dev/\1@' | sed -e :a -e '$!N; s/\n/|/; ta'))" | sort -k2n | tr '\n' ',' | sed 's/,$//' | sed 's@,/@, /@')

# this is a debconf-compatible script
. /usr/share/debconf/confmodule

# template for user prompt
cat > /tmp/deblive.template <<'!EOF!'
Template: deblive/disksel
Type: select
Choices: ${DISK_LIST}
Description:
 Select system disk

Template: deblive/disksel_title
Type: text
Description: Partitioning
!EOF!

# load template
db_x_loadtemplatefile /tmp/deblive.template deblive

# set title
db_settitle deblive/disksel_title

# prompt
db_input critical deblive/disksel
db_go

# get answer to $RET
db_get deblive/disksel

echo "$(echo "$RET" | head -n 1 | cut -f1)" >> /tmp/disksel.txt
