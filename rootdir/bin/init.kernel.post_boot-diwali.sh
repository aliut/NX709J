#=============================================================================
# Copyright (c) 2021 Qualcomm Technologies, Inc.
# All Rights Reserved.
# Confidential and Proprietary - Qualcomm Technologies, Inc.
#=============================================================================

function configure_zram_parameters() {
	MemTotalStr=`cat /proc/meminfo | grep MemTotal`
	MemTotal=${MemTotalStr:16:8}

	low_ram=`getprop ro.config.low_ram`

	# Zram disk - 75% for Go and < 2GB devices .
	# For >2GB Non-Go devices, size = 50% of RAM size. Limit the size to 4GB.
	# And enable lz4 zram compression for Go targets.

	let RamSizeGB="( $MemTotal / 1048576 ) + 1"
	diskSizeUnit=M
	if [ $RamSizeGB -le 2 ]; then
		let zRamSizeMB="( $RamSizeGB * 1024 ) * 3 / 4"
	else
		let zRamSizeMB="( $RamSizeGB * 1024 ) / 2"
	fi

	# use MB avoid 32 bit overflow
	if [ $zRamSizeMB -gt 4096 ]; then
		let zRamSizeMB=4096
	fi

	if [ "$low_ram" == "true" ]; then
		echo lz4 > /sys/block/zram0/comp_algorithm
	fi

	if [ -f /sys/block/zram0/disksize ]; then
		if [ -f /sys/block/zram0/use_dedup ]; then
			echo 1 > /sys/block/zram0/use_dedup
		fi
		#echo "$zRamSizeMB""$diskSizeUnit" > /sys/block/zram0/disksize
		if [ $RamSizeGB -le 10 ]; then
		   echo "$zRamSizeMB""$diskSizeUnit" > /sys/block/zram0/disksize
		else
		   echo "6144M" > /sys/block/zram0/disksize
		fi

		# ZRAM may use more memory than it saves if SLAB_STORE_USER
		# debug option is enabled.
		if [ -e /sys/kernel/slab/zs_handle ]; then
			echo 0 > /sys/kernel/slab/zs_handle/store_user
		fi
		if [ -e /sys/kernel/slab/zspage ]; then
			echo 0 > /sys/kernel/slab/zspage/store_user
		fi

		mkswap /dev/block/zram0
		swapon /dev/block/zram0 -p 32758
	fi
}

function configure_read_ahead_kb_values() {
	MemTotalStr=`cat /proc/meminfo | grep MemTotal`
	MemTotal=${MemTotalStr:16:8}

	dmpts=$(ls /sys/block/*/queue/read_ahead_kb | grep -e dm -e mmc)

	# Set 128 for <= 3GB &
	# set 512 for >= 4GB targets.
	if [ $MemTotal -le 3145728 ]; then
		ra_kb=128
	else
		ra_kb=512
	fi
	if [ -f /sys/block/mmcblk0/bdi/read_ahead_kb ]; then
		echo $ra_kb > /sys/block/mmcblk0/bdi/read_ahead_kb
	fi
	if [ -f /sys/block/mmcblk0rpmb/bdi/read_ahead_kb ]; then
		echo $ra_kb > /sys/block/mmcblk0rpmb/bdi/read_ahead_kb
	fi
	for dm in $dmpts; do
		echo $ra_kb > $dm
	done
}

function configure_memory_parameters() {
	# Set Memory parameters.
	#
	# Set per_process_reclaim tuning parameters
	# All targets will use vmpressure range 50-70,
	# All targets will use 512 pages swap size.
	#
	# Set Low memory killer minfree parameters
	# 32 bit Non-Go, all memory configurations will use 15K series
	# 32 bit Go, all memory configurations will use uLMK + Memcg
	# 64 bit will use Google default LMK series.
	#
	# Set ALMK parameters (usually above the highest minfree values)
	# vmpressure_file_min threshold is always set slightly higher
	# than LMK minfree's last bin value for all targets. It is calculated as
	# vmpressure_file_min = (last bin - second last bin ) + last bin
	#
	# Set allocstall_threshold to 0 for all targets.
	#

	ProductName=`getprop ro.product.name`

	configure_zram_parameters
	configure_read_ahead_kb_values
	echo 100 > /proc/sys/vm/swappiness

        # Disable wsf  beacause we are using efk.
        # wsf Range : 1..1000. So set to bare minimum value 1.
        echo 1 > /proc/sys/vm/watermark_scale_factor

	#Spawn 2 kswapd threads which can help in fast reclaiming of pages
	echo 2 > /proc/sys/vm/kswapd_threads
}

rev=`cat /sys/devices/soc0/revision`
ddr_type=`od -An -tx /proc/device-tree/memory/ddr_device_type`
ddr_type4="07"
ddr_type5="08"

# Core control parameters for gold
echo 2 > /sys/devices/system/cpu/cpu4/core_ctl/min_cpus
echo 60 > /sys/devices/system/cpu/cpu4/core_ctl/busy_up_thres
echo 30 > /sys/devices/system/cpu/cpu4/core_ctl/busy_down_thres
echo 100 > /sys/devices/system/cpu/cpu4/core_ctl/offline_delay_ms
echo 3 > /sys/devices/system/cpu/cpu4/core_ctl/task_thres

# Core control parameters for gold+
echo 0 > /sys/devices/system/cpu/cpu7/core_ctl/min_cpus
echo 60 > /sys/devices/system/cpu/cpu7/core_ctl/busy_up_thres
echo 30 > /sys/devices/system/cpu/cpu7/core_ctl/busy_down_thres
echo 100 > /sys/devices/system/cpu/cpu7/core_ctl/offline_delay_ms
echo 1 > /sys/devices/system/cpu/cpu7/core_ctl/task_thres

# Controls how many more tasks should be eligible to run on gold CPUs
# w.r.t number of gold CPUs available to trigger assist (max number of
# tasks eligible to run on previous cluster minus number of CPUs in
# the previous cluster).
#
# Setting to 1 by default which means there should be at least
# 4 tasks eligible to run on gold cluster (tasks running on gold cores
# plus misfit tasks on silver cores) to trigger assitance from gold+.
echo 1 > /sys/devices/system/cpu/cpu7/core_ctl/nr_prev_assist_thresh

# Disable Core control on silver
echo 0 > /sys/devices/system/cpu/cpu0/core_ctl/enable

# Setting b.L scheduler parameters
echo 65 85 > /proc/sys/walt/sched_downmigrate
echo 71 95 > /proc/sys/walt/sched_upmigrate
echo 85 > /proc/sys/walt/sched_group_downmigrate
echo 100 > /proc/sys/walt/sched_group_upmigrate
echo 1 > /proc/sys/walt/sched_walt_rotate_big_tasks
echo 0 > /proc/sys/walt/sched_coloc_busy_hysteresis_enable_cpus

# cpuset parameters
echo 0-3 > /dev/cpuset/background/cpus
echo 0-3 > /dev/cpuset/system-background/cpus

# Turn off scheduler boost at the end
echo 0 > /proc/sys/walt/sched_boost

# Reset the RT boost, which is 1024 (max) by default.
echo 0 > /proc/sys/kernel/sched_util_clamp_min_rt_default

# configure governor settings for silver cluster
echo "walt" > /sys/devices/system/cpu/cpufreq/policy0/scaling_governor
echo 0 > /sys/devices/system/cpu/cpufreq/policy0/walt/down_rate_limit_us
echo 0 > /sys/devices/system/cpu/cpufreq/policy0/walt/up_rate_limit_us
echo 1094400 > /sys/devices/system/cpu/cpufreq/policy0/walt/hispeed_freq
echo 614400 > /sys/devices/system/cpu/cpufreq/policy0/scaling_min_freq
echo 0 > /sys/devices/system/cpu/cpufreq/policy0/walt/pl

# configure input boost settings
echo 1094400 0 0 0 0 0 0 0 > /proc/sys/walt/input_boost/input_boost_freq
echo 120 > /proc/sys/walt/input_boost/input_boost_ms

# configure governor settings for gold cluster
echo "walt" > /sys/devices/system/cpu/cpufreq/policy4/scaling_governor
echo 0 > /sys/devices/system/cpu/cpufreq/policy4/walt/down_rate_limit_us
echo 0 > /sys/devices/system/cpu/cpufreq/policy4/walt/up_rate_limit_us
echo 1132800 > /sys/devices/system/cpu/cpufreq/policy4/walt/hispeed_freq
echo 652800 > /sys/devices/system/cpu/cpufreq/policy4/scaling_min_freq
echo 85 > /sys/devices/system/cpu/cpufreq/policy4/walt/hispeed_load
echo -6 > /sys/devices/system/cpu/cpufreq/policy4/walt/boost
echo 0 > /sys/devices/system/cpu/cpufreq/policy4/walt/rtg_boost_freq
echo 0 > /sys/devices/system/cpu/cpufreq/policy4/walt/pl

# configure governor settings for gold+ cluster
echo "walt" > /sys/devices/system/cpu/cpufreq/policy7/scaling_governor
echo 0 > /sys/devices/system/cpu/cpufreq/policy7/walt/down_rate_limit_us
echo 0 > /sys/devices/system/cpu/cpufreq/policy7/walt/up_rate_limit_us
echo 1401600 > /sys/devices/system/cpu/cpufreq/policy7/walt/hispeed_freq
echo 768000 > /sys/devices/system/cpu/cpufreq/policy7/scaling_min_freq
echo 85 > /sys/devices/system/cpu/cpufreq/policy7/walt/hispeed_load
echo -6 > /sys/devices/system/cpu/cpufreq/policy7/walt/boost
echo 0 > /sys/devices/system/cpu/cpufreq/policy7/walt/rtg_boost_freq
echo 0 > /sys/devices/system/cpu/cpufreq/policy7/walt/pl

# colocation V3 settings
echo 614400 > /sys/devices/system/cpu/cpufreq/policy0/walt/rtg_boost_freq
echo 51 > /proc/sys/kernel/sched_min_task_util_for_boost
echo 35 > /proc/sys/kernel/sched_min_task_util_for_colocation
echo 20000000 > /proc/sys/kernel/sched_task_unfilter_period

# Enable conservative pl
echo 1 > /proc/sys/kernel/sched_conservative_pl

# configure bus-dcvs
bus_dcvs="/sys/devices/system/cpu/bus_dcvs"

for device in $bus_dcvs/*
do
	cat $device/hw_min_freq > $device/boost_freq
done

for llccbw in $bus_dcvs/LLCC/*bwmon-llcc
do
	echo "4577 7110 9155 12298 14236 15258" > $llccbw/mbps_zones
	echo 4 > $llccbw/sample_ms
	echo 68 > $llccbw/io_percent
	echo 20 > $llccbw/hist_memory
	echo 0 > $llccbw/hyst_length
	echo 80 > $llccbw/down_thres
	echo 0 > $llccbw/guard_band_mbps
	echo 250 > $llccbw/up_scale
	echo 1600 > $llccbw/idle_mbps
	echo 40 > $llccbw/window_ms
done

for ddrbw in $bus_dcvs/DDR/*bwmon-ddr
do
	if [ ${ddr_type:4:2} == $ddr_type4 ]; then
		echo "1144 1720 2086 2929 3879 5931 6515 8136" > $llccbw/bw_hwmon/mbps_zones
	elif [ ${ddr_type:4:2} == $ddr_type5 ]; then
		echo "1720 2086 2929 3879 5931 6515 7980 12191" > $llccbw/bw_hwmon/mbps_zones
	fi
	echo 4 > $ddrbw/sample_ms
	echo 68 > $ddrbw/io_percent
	echo 20 > $ddrbw/hist_memory
	echo 0 > $ddrbw/hyst_length
	echo 80 > $ddrbw/down_thres
	echo 0 > $ddrbw/guard_band_mbps
	echo 250 > $ddrbw/up_scale
	echo 1600 > $ddrbw/idle_mbps
	echo 48 > $ddrbw/window_ms
done

for latfloor in $bus_dcvs/*/*latfloor
do
	echo 25000 > $latfloor/ipm_ceil
done

for l3gold in $bus_dcvs/L3/*gold
do
	echo 4000 > $l3gold/ipm_ceil
done

for l3prime in $bus_dcvs/L3/*prime
do
	echo 20000 > $l3prime/ipm_ceil
done

for ddrprime in $bus_dcvs/DDR/*prime
do
	echo 25 > $ddrprime/freq_scale_pct
	echo 1881 > $ddrprime/freq_scale_limit_mhz
done

for qosgold in $bus_dcvs/DDRQOS/*gold
do
	echo 50 > $qosgold/ipm_ceil
done

=============================================

#set s2idle as default suspend mode
echo s2idle > /sys/power/mem_sleep

# Enable LPM
echo N > /sys/devices/system/cpu/qcom_lpm/parameters/sleep_disabled

configure_memory_parameters

# Let kernel know our image version/variant/crm_version
if [ -f /sys/devices/soc0/select_image ]; then
	image_version="10:"
	image_version+=`getprop ro.build.id`
	image_version+=":"
	image_version+=`getprop ro.build.version.incremental`
	image_variant=`getprop ro.product.name`
	image_variant+="-"
	image_variant+=`getprop ro.build.type`
	oem_version=`getprop ro.build.version.codename`
	echo 10 > /sys/devices/soc0/select_image
	echo $image_version > /sys/devices/soc0/image_version
	echo $image_variant > /sys/devices/soc0/image_variant
	echo $oem_version > /sys/devices/soc0/image_crm_version
fi

# Change console log level as per console config property
console_config=`getprop persist.console.silent.config`
case "$console_config" in
	"1")
		echo "Enable console config to $console_config"
		echo 0 > /proc/sys/kernel/printk
	;;
	*)
		echo "Enable console config to $console_config"
	;;
esac

setprop vendor.post_boot.parsed 1
