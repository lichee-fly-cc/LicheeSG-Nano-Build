#!/bin/bash -e
# Minimal headless companion/air build with wfb-ng support and os04a10 as the
# main camera sensor (wifi broadcast video link).
# Based on the build-dap.sh trimming:
#   - kernel: licheervnano-rtl8812au-wfb_ng-5.10.y branch (rtl8812au + wfb_ng)
#   - wfb-ng binaries (wfb_tx/wfb_rx/wfb_keygen) added as a buildroot package
#   - mavp2p (static riscv64 binary, optional, --no-mavp2p)
#   - sensor: ov_os04a10 tuning bin + sensor_cfg.ini from the nanokvm overlay
#   - no TPU/opencv/qt5, no audio stack, no display/panel fip variants
# Boot flags on the SD boot partition: /boot/wfb.air (+ optional /boot/wfb.channel)

export SG_BOARD_FAMILY=sg200x
export SG_BOARD_LINK=sg2002_licheervnano_sd

sdkver=keep
maixcdk=n
osstar=n
shrink=y
mavp2p=y
tailscale=n
tpudemo=n
tpusdk=n
while [ "$#" -gt 0 ]; do
	case "$1" in
	--board=*|--board-link=*)
		export SG_BOARD_LINK=`echo $1 | cut -d '=' -f 2-`
		shift
		;;
	--sdk-ver=*|--sdkver=*)
		sdkver=`echo $1 | cut -d '=' -f 2-`
		shift
		;;
	--maix-cdk|--maixcdk)
		shift
		maixcdk=y
		;;
	--no-maix-cdk|--no-maixcdk)
		shift
		maixcdk=n
		;;
	--oss-tar|--osstar)
		shift
		osstar=y
		;;
	--no-oss-tar|--no-osstar)
		shift
		osstar=n
		;;
	--shrink)
		shift
		shrink=y
		;;
	--no-shrink)
		shift
		shrink=n
		;;
	--mavp2p|--mavlink)
		shift
		mavp2p=y
		;;
	--no-mavp2p|--no-mavlink)
		shift
		mavp2p=n
		;;
	--tailscale)
		shift
		tailscale=y
		;;
	--no-tailscale)
		shift
		tailscale=n
		;;
	--tpu-demo|--tpudemo)
		shift
		tpudemo=y
		;;
	--no-tpu-demo|--no-tpudemo)
		shift
		tpudemo=n
		;;
	--tpu-sdk|--tpusdk)
		shift
		tpusdk=y
		;;
	--no-tpu-sdk|--no-tpusdk)
		shift
		tpusdk=n
		;;
	*)
		break
		;;
	esac
done

for p in / /usr/ /usr/local/ ; do
  if echo $PATH | grep -q ${p}bin ; then
    if ! echo $PATH | grep -q ${p}sbin ; then
      export PATH=${p}sbin:$PATH
    fi
  fi
done

if echo ${SG_BOARD_LINK} | grep -q -E '^cv180' ; then
  export SG_BOARD_FAMILY=cv180x
fi
if echo ${SG_BOARD_LINK} | grep -q -E '^sg200' ; then
  export SG_BOARD_FAMILY=sg200x
fi

# kernel: switch to the dedicated wfb-ng branch
# (licheervnano-merged-5.10.y + rtl8812au driver with wfb_ng patches)
KBRANCH=licheervnano-rtl8812au-wfb_ng-5.10.y
if [ -e linux_5.10/.git ]; then
  git -C linux_5.10 fetch origin $KBRANCH 2>/dev/null || true
  git -C linux_5.10 checkout -q -f -B $KBRANCH origin/$KBRANCH
fi

if [ -e prepare-licheesgnano.sh ]; then
  . ./prepare-licheesgnano.sh
fi

cd build

# board config for maixcdk
if [ $maixcdk = y ]; then
  if ! grep -q "board" tools/common/sd_tools/genimage_rootless.cfg ; then
    sed -i s/'\t\t\t"usb.dev",'/'\t\t\t"usb.dev",\n\t\t\t"board",'/g tools/common/sd_tools/genimage_rootless.cfg
  fi
  if ! grep -q "board" tools/common/sd_tools/sd_gen_burn_image_rootless.sh ; then
    sed -i 's| \${output_dir}/input/usb.dev$| ${output_dir}/input/usb.dev\necho "id=maixcam" > ${output_dir}/input/board\necho "name=MaixCAM" >> ${output_dir}/input/board\necho "panel=st7701_hd228001c31" >> ${output_dir}/input/board|g' tools/common/sd_tools/sd_gen_burn_image_rootless.sh
  fi
fi
# set mipi sensor flag
if echo ${SG_BOARD_LINK} | grep -q lichee ; then
  sed -i /epsilon/d tools/common/sd_tools/genimage_rootless.cfg
  sed -i /epsilon/d tools/common/sd_tools/sd_gen_burn_image_rootless.sh
fi
# disable gt9xx
sed -i /gt9xx/d tools/common/sd_tools/genimage_rootless.cfg
sed -i /gt9xx/d tools/common/sd_tools/sd_gen_burn_image_rootless.sh
# remove logo
sed -i /logo.jpeg/d tools/common/sd_tools/genimage_rootless.cfg
# keep usb.rndis + usb.ncm: gadget network console is useful in the field
# no wifi.sta / wifi.ap: S30wifi stays idle, wfb-ng owns the radio
sed -i /'wifi.sta'/d tools/common/sd_tools/genimage_rootless.cfg
sed -i /'wifi.sta'/d tools/common/sd_tools/sd_gen_burn_image_rootless.sh
# add wfb.air boot flag (enables the wfb-ng air-side init script)
if ! grep -q "wfb.air" tools/common/sd_tools/genimage_rootless.cfg ; then
  sed -i s/'\t\t\t"usb.dev",'/'\t\t\t"usb.dev",\n\t\t\t"wfb.air",'/g tools/common/sd_tools/genimage_rootless.cfg
  sed -i 's| \${output_dir}/input/usb.dev$| ${output_dir}/input/usb.dev\ntouch ${output_dir}/input/wfb.air|g' tools/common/sd_tools/sd_gen_burn_image_rootless.sh
fi
# set hostname prefix
if ! grep -q "hostname.prefix" tools/common/sd_tools/genimage_rootless.cfg ; then
  sed -i s/'\t\t\t"usb.dev",'/'\t\t\t"hostname.prefix",\n\t\t\t"usb.dev",'/g tools/common/sd_tools/genimage_rootless.cfg
fi
if ! grep -q "hostname.prefix" tools/common/sd_tools/sd_gen_burn_image_rootless.sh ; then
  sed -i 's|^touch \${output_dir}/input/usb.dev$|echo -n wfb > ${output_dir}/input/hostname.prefix\ntouch \${output_dir}/input/usb.dev|g' tools/common/sd_tools/sd_gen_burn_image_rootless.sh
fi

# kernel: trim unused subsystems, keep USB serial/acm for FC telemetry
# and the whole video stack (CONFIG_VIDEO_CVITEK + CIF + SNS_I2C) for the
# os04a10 camera; only the display framebuffer is disabled
offcnf="CONFIG_IP_VS
CONFIG_WIREGUARD
CONFIG_PACKET_DIAG
CONFIG_UNIX_DIAG
CONFIG_NETLINK_DIAG
CONFIG_NET_IPGRE
CONFIG_VXLAN
CONFIG_FB_CVITEK
CONFIG_JFFS2_FS
CONFIG_SQUASHFS"

for c in $offcnf ; do
  sed -i s/'^'$c'=.$'/'# '$c' is not set'/g boards/${SG_BOARD_FAMILY}/${SG_BOARD_LINK}/linux/*${SG_BOARD_LINK}_defconfig
done
# make sure the wfb-ng radio driver is there
if ! grep -q '^CONFIG_RTL8812AU=m' boards/${SG_BOARD_FAMILY}/${SG_BOARD_LINK}/linux/*${SG_BOARD_LINK}_defconfig ; then
  echo 'CONFIG_RTL8812AU=m' >> boards/${SG_BOARD_FAMILY}/${SG_BOARD_LINK}/linux/*${SG_BOARD_LINK}_defconfig
fi

# u-boot: no display on an air unit
offubt="BMP
VIDCONSOLE
CVI_VO
DISPLAY
LOGO
VIDEO"

for c in $offubt ; do
  sed -i /$c/d boards/${SG_BOARD_FAMILY}/${SG_BOARD_LINK}/u-boot/*${SG_BOARD_LINK}_defconfig
done

# Expand user space RAM from 128MB to 160MB
if ! grep -q -E '^CONFIG_DDR_64MB_SIZE=y' boards/${SG_BOARD_FAMILY}/${SG_BOARD_LINK}/${SG_BOARD_LINK}_defconfig ; then
  sed -i s/'ION_SIZE = .* . SIZE_1M'/'ION_SIZE = 75 * SIZE_1M'/g boards/${SG_BOARD_FAMILY}/${SG_BOARD_LINK}/memmap.py
  sed -i s/'BOOTLOGO_SIZE = .* . SIZE_1K'/'BOOTLOGO_SIZE = 5632 * SIZE_1K'/g boards/${SG_BOARD_FAMILY}/${SG_BOARD_LINK}/memmap.py
fi

# main sensor: os04a10 — enable its isp tuning bin, drop the gc4653 default
bdefcfg=boards/${SG_BOARD_FAMILY}/${SG_BOARD_LINK}/${SG_BOARD_LINK}_defconfig
sed -i s/'^CONFIG_SENSOR_TUNING_PARAM_cv181x_src_gcore_gc4653=y'/'# CONFIG_SENSOR_TUNING_PARAM_cv181x_src_gcore_gc4653 is not set'/g $bdefcfg
# the stock line is malformed ("# CONFIG...=y"), normalize it to a real =y
sed -i s/'^# CONFIG_SENSOR_TUNING_PARAM_sg200x_src_ov_os04a10=y'/'CONFIG_SENSOR_TUNING_PARAM_sg200x_src_ov_os04a10=y'/g $bdefcfg
if ! grep -q '^CONFIG_SENSOR_TUNING_PARAM_sg200x_src_ov_os04a10=y' $bdefcfg ; then
  echo 'CONFIG_SENSOR_TUNING_PARAM_sg200x_src_ov_os04a10=y' >> $bdefcfg
fi
# other sensors are not needed on an air unit
for s in GCORE_GC2083 GCORE_GC4653 OV_OV2685 OV_OV5647 LONTIUM_LT6911 SMS_SC035GS ; do
  sed -i s/'^CONFIG_SENSOR_'$s'=y'/'# CONFIG_SENSOR_'$s' is not set'/g $bdefcfg
done
grep -E '^CONFIG_SENSOR_|^CONFIG_SENSOR_TUNING' $bdefcfg
cd ..

cd ramdisk
sed -i s/'^sleep 0'/'#sleep 0'/g initramfs/*/init
cd ..

BR_OUTPUT_DIR=output

source build/cvisetup.sh
defconfig ${SG_BOARD_LINK}

cd buildroot

# trim init scripts: only display/periphery modules are disabled,
# the camera chain (mipi_rx, snsr_i2c, vi, vpss, dwa, rgn, vcodec, jpeg,
# vc_driver) must stay loaded for the os04a10 + wfb-ng video link
modoff="soph_fb.ko
soph_ive.ko
soph_mipi_tx.ko
soph_tpu.ko
soph_vo.ko
soph_saradc.ko"

for m in $modoff; do
  sed -i s/'insmod '$m/'#insmod '$m/g board/cvitek/SG200X/overlay/etc/init.d/S00kmod
done
rm -f board/cvitek/SG200X/overlay/etc/init.d/S04backlight
rm -f board/cvitek/SG200X/overlay/etc/init.d/S04fb
rm -f board/cvitek/SG200X/overlay/etc/init.d/S05tp
rm -f board/cvitek/SG200X/overlay/etc/init.d/S99*test
rm -f board/cvitek/SG200X/overlay/etc/init.d/uvc_tool.sh
rm -f board/cvitek/SG200X/overlay/etc/init.d/uvc-gadget-server.elf
rm -f board/cvitek/SG200X/overlay/etc/init.d/uvc-gadget-server.tar.xz
rm -f board/cvitek/SG200X/overlay/etc/init.d/S*kvm*
rm -f board/cvitek/SG200X/overlay/etc/init.d/S*ssdp*
rm -f board/cvitek/SG200X/overlay/etc/init.d/S*tailscale*
rm -f board/cvitek/SG200X/overlay/etc/init.d/S*usbhid*

rm -f ${BR_OUTPUT_DIR}/target/etc/init.d/S*
rm -f ${BR_OUTPUT_DIR}/target/etc/init.d/uvc*

cat <<\EOF > board/cvitek/SG200X/overlay/etc/init.d/S05ethmod
#!/bin/sh

if [ "$1" = "start" ]
then
	. /etc/profile
	printf "load eth kernel module: "
	cd /mnt/system/ko/
	insmod stmmac-platform.ko
	insmod dwmac-thead.ko
	insmod dwmac-cvitek.ko
	echo "OK"
	exit 0
fi
EOF
chmod ugo+rx board/cvitek/SG200X/overlay/etc/init.d/S05ethmod

cat <<\EOF > board/cvitek/SG200X/overlay/etc/init.d/S60wfbng
#!/bin/sh

WFB_BIN=/usr/bin
WFB_WLAN=${WFB_WLAN:-wlan0}

start() {
	if [ ! -e /boot/wfb.air ]
	then
		return 0
	fi
	. /etc/profile
	printf "wfb-ng air: "
	ch=`cat /boot/wfb.channel 2>/dev/null || echo 161`
	[ -e /etc/drone.key ] || (cd /etc && ${WFB_BIN}/wfb_keygen)
	ip link set ${WFB_WLAN} down
	iw dev ${WFB_WLAN} set type monitor
	ip link set ${WFB_WLAN} up
	iw dev ${WFB_WLAN} set channel $ch
	# video downlink, port 5600
	${WFB_BIN}/wfb_tx -K /etc/drone.key -p 1 -u 5600 -i 76692005 \
		-B 20 -M 0 -S 1 -L 1 -G long -k 1 -n 8 ${WFB_WLAN} &
	echo "OK (channel $ch)"
}

stop() {
	killall wfb_tx 2>/dev/null || true
}

if [ "$1" = "start" ]
then
	start
elif [ "$1" = "stop" ]
then
	stop
fi
EOF
chmod ugo+rx board/cvitek/SG200X/overlay/etc/init.d/S60wfbng

if [ $mavp2p = y ]; then
cat <<\EOF > board/cvitek/SG200X/overlay/etc/init.d/S70mavp2p
#!/bin/sh

start() {
	if [ ! -e /boot/wfb.air ]
	then
		return 0
	fi
	. /etc/profile
	printf "mavp2p: "
	# default: FC serial <-> loopback udp (wfb telemetry link)
	args="serial:///dev/ttyS1@115200 udp:127.0.0.1:14550 udp:127.0.0.1:14551"
	[ -e /boot/mavp2p.args ] && args=`cat /boot/mavp2p.args`
	/usr/bin/mavp2p $args &
	echo "OK"
}

stop() {
	killall mavp2p 2>/dev/null || true
}

if [ "$1" = "start" ]
then
	start
elif [ "$1" = "stop" ]
then
	stop
fi
EOF
chmod ugo+rx board/cvitek/SG200X/overlay/etc/init.d/S70mavp2p
fi

sed -i s/'^acm'/'#acm'/g board/cvitek/SG200X/overlay/etc/inittab

# wfb-ng buildroot package (kept in the tree, not committed)
mkdir -p package/wfb-ng
cat <<\EOF > package/wfb-ng/Config.in
config BR2_PACKAGE_WFB_NG
	bool "wfb-ng"
	select BR2_PACKAGE_LIBSODIUM
	select BR2_PACKAGE_LIBPCAP
	help
	  WFB-NG is the next generation of long distance packet radio link
	  based on wifi 802.11 (monitor mode), used for drone video/telemetry.
	  Air side binaries: wfb_tx, wfb_rx, wfb_keygen.
	  https://github.com/svpcom/wfb-ng
EOF
cat <<\EOF > package/wfb-ng/wfb-ng.mk
################################################################################
#
# wfb-ng
#
################################################################################

WFB_NG_VERSION = wfb-ng-25.01.2
WFB_NG_SITE = $(call github,svpcom,wfb-ng,$(WFB_NG_VERSION))
WFB_NG_LICENSE = GPL-3.0+
WFB_NG_DEPENDENCIES = libsodium libpcap

define WFB_NG_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) $(TARGET_CONFIGURE_OPTS) -C $(@D) \
		wfb_tx wfb_rx wfb_keygen wfb_tx_cmd
endef

define WFB_NG_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/wfb_tx $(TARGET_DIR)/usr/bin/wfb_tx
	$(INSTALL) -D -m 0755 $(@D)/wfb_rx $(TARGET_DIR)/usr/bin/wfb_rx
	$(INSTALL) -D -m 0755 $(@D)/wfb_keygen $(TARGET_DIR)/usr/bin/wfb_keygen
	$(INSTALL) -D -m 0755 $(@D)/wfb_tx_cmd $(TARGET_DIR)/usr/bin/wfb_tx_cmd
endef

$(eval $(generic-package))
EOF
if ! grep -q 'package/wfb-ng/Config.in' package/Config.in ; then
  sed -i s#'^\(\s*source "package/mavlink-router/Config.in"\)$'#'\1\n\tsource "package/wfb-ng/Config.in"'# package/Config.in
fi

# defconfig: wfb-ng and its dependencies
for p in 'BR2_PACKAGE_LIBSODIUM=y' 'BR2_PACKAGE_LIBPCAP=y' 'BR2_PACKAGE_WFB_NG=y' ; do
  if ! grep -q "^$p$" configs/${BR_DEFCONFIG} ; then
    sed -i s/'^BR2_PACKAGE_PARTED=y'/"$p\nBR2_PACKAGE_PARTED=y"/g configs/${BR_DEFCONFIG}
  fi
done
if [ $tailscale = y ]; then
  sed -i s/'^BR2_PACKAGE_PARTED=y'/'BR2_PACKAGE_TAILSCALE_RISCV64=y\nBR2_PACKAGE_PARTED=y'/g configs/${BR_DEFCONFIG}
fi
if [ $tpudemo = y ]; then
  sed -i s/'^# BR2_PACKAGE_TPUDEMO_SG200X is not set'/'BR2_PACKAGE_TPUDEMO_SG200X=y'/g configs/${BR_DEFCONFIG}
else
  sed -i s/'^BR2_PACKAGE_TPUDEMO_SG200X=y'/'# BR2_PACKAGE_TPUDEMO_SG200X is not set'/g configs/${BR_DEFCONFIG}
fi
if [ $tpusdk = y ]; then
  sed -i s/'^# BR2_PACKAGE_SOPHGO_LIBRARY is not set'/'BR2_PACKAGE_SOPHGO_LIBRARY=y'/g configs/${BR_DEFCONFIG}
else
  sed -i s/'^BR2_PACKAGE_SOPHGO_LIBRARY=y'/'# BR2_PACKAGE_SOPHGO_LIBRARY is not set'/g configs/${BR_DEFCONFIG}
fi
if [ $shrink = y ]; then
  sed -i /'^BR2_PACKAGE_PYTHON_'/d configs/${BR_DEFCONFIG}

  sed -i s/'^BR2_PACKAGE_PYTHON3_PY_PYC=y$'/'BR2_PACKAGE_PYTHON3_PY_PYC=y'\
'\nBR2_PACKAGE_PYTHON_REQUESTS=y'\
'\nBR2_PACKAGE_PYTHON_REQUESTS_OAUTHLIB=y'\
'\nBR2_PACKAGE_PYTHON_REQUESTS_TOOLBELT=y'/g configs/${BR_DEFCONFIG}

  sed -i /'^BR2_PACKAGE_GDB'/d configs/${BR_DEFCONFIG}
  sed -i /'^BR2_PACKAGE_HOST_GDB'/d configs/${BR_DEFCONFIG}
  sed -i /'^BR2_GDB_'/d configs/${BR_DEFCONFIG}

  # aircrack-ng is kept: airmon-ng is handy for radio debugging
  sed -i /'^BR2_PACKAGE_MOSH'/d configs/${BR_DEFCONFIG}
  sed -i /'^BR2_PACKAGE_LRZSZ'/d configs/${BR_DEFCONFIG}
  sed -i /'^BR2_PACKAGE_DHRYSTONE'/d configs/${BR_DEFCONFIG}
  sed -i /'^BR2_PACKAGE_COREMARK'/d configs/${BR_DEFCONFIG}
  sed -i /'^BR2_PACKAGE_RAMSPEED'/d configs/${BR_DEFCONFIG}
  sed -i /'^BR2_PACKAGE_SQUASHFS'/d configs/${BR_DEFCONFIG}
  sed -i /'^BR2_PACKAGE_LCDTEST'/d configs/${BR_DEFCONFIG}
  sed -i /'^BR2_PACKAGE_ASCII_INVADERS'/d configs/${BR_DEFCONFIG}
  sed -i /'^BR2_PACKAGE_GNUCHESS'/d configs/${BR_DEFCONFIG}
  sed -i /'^BR2_PACKAGE_SL'/d configs/${BR_DEFCONFIG}
  sed -i /'^BR2_PACKAGE_XORCURSES'/d configs/${BR_DEFCONFIG}
  sed -i /'^BR2_PACKAGE_STRESS'/d configs/${BR_DEFCONFIG}
  sed -i /'^BR2_PACKAGE_EXPECT'/d configs/${BR_DEFCONFIG}
  sed -i /'^BR2_PACKAGE_TCL'/d configs/${BR_DEFCONFIG}

  sed -i s/'BR2_PACKAGE_OPENCV4_BUILD_TESTS=y'/'# BR2_PACKAGE_OPENCV4_BUILD_TESTS is not set'/g configs/${BR_DEFCONFIG}
  sed -i s/'BR2_PACKAGE_OPENCV4_BUILD_PERF_TESTS=y'/'# BR2_PACKAGE_OPENCV4_BUILD_TESTS is not set'/g configs/${BR_DEFCONFIG}

  sed -i /'BR2_PACKAGE_OPENCV'/d configs/${BR_DEFCONFIG}
  sed -i /'BR2_PACKAGE_QT5'/d configs/${BR_DEFCONFIG}

  sed -i /'BR2_PACKAGE_BLUEZ'/d configs/${BR_DEFCONFIG}
  sed -i /'BR2_PACKAGE_LFTP'/d configs/${BR_DEFCONFIG}
  sed -i /'BR2_PACKAGE_VSFTPD'/d configs/${BR_DEFCONFIG}
  sed -i /'BR2_PACKAGE_LLDPD'/d configs/${BR_DEFCONFIG}
  sed -i /'BR2_PACKAGE_SSDP_RESPONDER'/d configs/${BR_DEFCONFIG}
  sed -i /'BR2_PACKAGE_UVC_GADGET'/d configs/${BR_DEFCONFIG}
  sed -i /'^BR2_PACKAGE_LIBQRENCODE'/d configs/${BR_DEFCONFIG}
  sed -i /'^BR2_PACKAGE_LIBWEBSOCKETS'/d configs/${BR_DEFCONFIG}
  sed -i /'^BR2_PACKAGE_FFMPEG'/d configs/${BR_DEFCONFIG}
  sed -i /'^BR2_PACKAGE_MPD'/d configs/${BR_DEFCONFIG}
  sed -i /'^BR2_PACKAGE_SHAIRPORT'/d configs/${BR_DEFCONFIG}
fi
cd ..

if [ -e cvi_rtsp ]; then
  # fix "fatal error: Can't find suitable multilib set"
  sed -i s/'-march=rv64imafdcvxthead -mcmodel=medany -mabi=lp64dv'/'-march=rv64imafdcv0p7xthead -mcmodel=medany -mabi=lp64d'/g cvi_rtsp/Makefile.inc
fi
if [ $osstar = y ]; then
  export OSS_TARBALL_REL=1
fi

# mavp2p: static riscv64 binary (Go >= 1.25 per go.mod, provisioned locally)
if [ $mavp2p = y ]; then
  GVER=1.25.3
  if [ ! -e host/go/bin/go ]; then
    echo "Downloading Go ${GVER} toolchain..."
    wget -q -O host/go.tar.gz https://go.dev/dl/go${GVER}.linux-amd64.tar.gz
    rm -rf host/go && mkdir -p host/go
    tar --strip-components=1 -C host/go -xzf host/go.tar.gz
    rm -f host/go.tar.gz
  fi
  if [ -d mavp2p/.git ]; then
    git -C mavp2p pull -q 2>/dev/null || true
  else
    git clone -q https://github.com/lichee-fly-cc/mavp2p mavp2p
  fi
  mkdir -p buildroot/board/cvitek/SG200X/overlay/usr/bin
  echo "Building mavp2p for riscv64..."
  (cd mavp2p && \
    CGO_ENABLED=0 GOOS=linux GOARCH=riscv64 \
    GOCACHE=`pwd`/../.ccache/go \
    ../host/go/bin/go build -trimpath -ldflags='-s -w' \
    -o ../buildroot/board/cvitek/SG200X/overlay/usr/bin/mavp2p .)
fi

# sensor_cfg.ini: os04a10 variant from the nanokvm overlay becomes the default
# (S02config copies sensor_cfg.ini.beta -> /mnt/data/sensor_cfg.ini on boot)
cp -v buildroot/package/nanokvm-sg200x/overlay/mnt/data/sensor_cfg.ini.OA \
      buildroot/board/cvitek/SG200X/overlay/mnt/data/sensor_cfg.ini.beta

build_all

cd build
git restore boards/${SG_BOARD_FAMILY}/${SG_BOARD_LINK}/memmap.py
git restore boards/${SG_BOARD_FAMILY}/${SG_BOARD_LINK}/${SG_BOARD_LINK}_defconfig
git restore boards/${SG_BOARD_FAMILY}/${SG_BOARD_LINK}/linux/*${SG_BOARD_LINK}_defconfig
git restore boards/${SG_BOARD_FAMILY}/${SG_BOARD_LINK}/u-boot/*${SG_BOARD_LINK}_defconfig
git restore tools/common/sd_tools/genimage_rootless.cfg
git restore tools/common/sd_tools/sd_gen_burn_image_rootless.sh
cd ..

cd ramdisk
git restore initramfs/*/init
cd ..

cd buildroot
rm -f ${BR_OUTPUT_DIR}/target/etc/init.d/S*kvm*
rm -f ${BR_OUTPUT_DIR}/target/etc/init.d/S*tailscale*
git restore board/cvitek/SG200X/overlay/etc/init.d
git restore board/cvitek/SG200X/overlay/etc/inittab 2>/dev/null || true
git restore board/cvitek/SG200X/overlay/mnt/data/sensor_cfg.ini.beta 2>/dev/null || true
git restore configs/${BR_DEFCONFIG}
# note: package/wfb-ng is untracked and survives the restore;
# the 'source' line in package/Config.in is re-added on the next run
cd ..

echo OK
