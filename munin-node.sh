#!/bin/sh
#
# Simple Bourne Shell script that implements Munin protocoll and
# some common Linux plugins.
#
# For latest version, see http://muninlite.sf.net/
#
# Copyright (c) 2007-2011 Rune Nordb?e Skillingstad <rune@skillingstad.no>
#
# Licensed under GPLv2 (see LICENSE file for full License)
#
# $Id: $
#

VERSION="1.0.4"

NTP_PEER="pool.ntp.org";

# if plugindir_ is present in $PLUGINS,
# iexecutables (scripts, binaries) matching the following pattern will be scanned and operated as plugins
PLUGINPATTERN=$(dirname $0)"/munin-node-plugin.d/*"

# Remove unwanted plugins from this list
PLUGINS="df cpu if_ if_err_ users load memory processes swap ipmi_temp hdd_temp plugindir_"
# ===== LIB FUNCTIONS =====
clean_fieldname() {
  echo "$@" | sed -e 's/^[^A-Za-z_]/_/' -e 's/[^A-Za-z0-9_]/_/g'
}

# ===== PLUGINS CODE =====

config_df() {
  echo "graph_title Disk usage in percent
graph_args --upper-limit 100 -l 0
graph_vlabel %
graph_category disk
graph_info This graph shows disk usage on the machine."
  for PART in $(df | grep '^/' | awk '{print $6}' | sed 1d)
  do
    PINFO=$(df $PART | tail -1);
    PNAME=$(echo $PINFO | cut -d\  -f1 | sed 's/\//_/g')
    echo "$PNAME.label $PART"
    echo "$PNAME.info $PNAME -> $PART"
    echo "$PNAME.warning 92"
    echo "$PNAME.critical 98"
  done
}
fetch_df() {
  for PART in $(df | grep '^/' | awk '{print $6}' | sed 1d)
  do
    PINFO=$(df $PART | tail -1);
    PNAME=$(echo $PINFO | cut -d\  -f1 | sed 's/[\/.-]/_/g')
    echo "$PNAME.value" $(echo $PINFO | cut -f5 -d\  | sed -e 's/\%//g')
  done
}
config_cpu() {
  extinfo=""
  if grep '^cpu \{1,\}[0-9]\{1,\} \{1,\}[0-9]\{1,\} \{1,\}[0-9]\{1,\} \{1,\}[0-9]\{1,\} \{1,\}[0-9]\{1,\} \{1,\}[0-9]\{1,\} \{1,\}[0-9]\{1,\}' /proc/stat >/dev/null 2>&1; then
    extinfo="iowait irq softirq"
  fi
  NCPU=$(($(grep '^cpu. ' /proc/stat | wc -l) - 1))
  if [ $NCPU = 0 ]; then NCPU=1; fi
  PERCENT=$(($NCPU * 100))
  graphlimit=$PERCENT
  SYSWARNING=$(($PERCENT * 30 / 100))
  SYSCRITICAL=$(($PERCENT * 50 / 100))
  USRWARNING=$(($PERCENT * 80 / 100))
  echo "graph_title CPU usage"
  echo "graph_order system user nice idle" $extinfo
  echo "graph_args --base 1000 -r --lower-limit 0 --upper-limit $graphlimit"
  echo "graph_vlabel %"
  echo "graph_scale no"
  echo "graph_info This graph shows how CPU time is spent."
  echo "graph_category system"
  echo "graph_period second"
  echo "system.label system"
  echo "system.draw AREA"
  echo "system.max 5000"
  echo "system.min 0"
  echo "system.type DERIVE"
  echo "system.warning $SYSWARNING"
  echo "system.critical $SYSCRITICAL"
  echo "system.info CPU time spent by the kernel in system activities"
  echo "user.label user"
  echo "user.draw STACK"
  echo "user.min 0"
  echo "user.max 5000"
  echo "user.warning $USRWARNING"
  echo "user.type DERIVE"
  echo "user.info CPU time spent by normal programs and daemons"
  echo "nice.label nice"
  echo "nice.draw STACK"
  echo "nice.min 0"
  echo "nice.max 5000"
  echo "nice.type DERIVE"
  echo "nice.info CPU time spent by nice(1)d programs"
  echo "idle.label idle"
  echo "idle.draw STACK"
  echo "idle.min 0"
  echo "idle.max 5000"
  echo "idle.type DERIVE"
  echo "idle.info Idle CPU time"
  if [ ! -z "$extinfo" ]; then
    echo "iowait.label iowait"
    echo "iowait.draw STACK"
    echo "iowait.min 0"
    echo "iowait.max 5000"
    echo "iowait.type DERIVE"
    echo "iowait.info CPU time spent waiting for I/O operations to finish"
    echo "irq.label irq"
    echo "irq.draw STACK"
    echo "irq.min 0"
    echo "irq.max 5000"
    echo "irq.type DERIVE"
    echo "irq.info CPU time spent handling interrupts"
    echo "softirq.label softirq"
    echo "softirq.draw STACK"
    echo "softirq.min 0"
    echo "softirq.max 5000"
    echo "softirq.type DERIVE"
    echo "softirq.info CPU time spent handling "batched" interrupts"
  fi
}
fetch_cpu() {
  extinfo=""
  if grep '^cpu \{1,\}[0-9]\{1,\} \{1,\}[0-9]\{1,\} \{1,\}[0-9]\{1,\} \{1,\}[0-9]\{1,\} \{1,\}[0-9]\{1,\} \{1,\}[0-9]\{1,\} \{1,\}[0-9]\{1,\}' /proc/stat >/dev/null 2>&1; then
    extinfo="iowait irq softirq"
  fi
  CINFO=$(grep '^cpu ' /proc/stat | cut -c6-)
  echo "user.value" $(echo "$CINFO" | cut -d\  -f1)
  echo "nice.value" $(echo "$CINFO" | cut -d\  -f2)
  echo "system.value" $(echo "$CINFO" | cut -d\  -f3)
  echo "idle.value" $(echo "$CINFO" | cut -d\  -f4)
  if [ ! -z "$extinfo" ]; then
    echo "iowait.value" $(echo "$CINFO" | cut -d\  -f5)
    echo "irq.value" $(echo "$CINFO" | cut -d\  -f6)
    echo "softirq.value" $(echo "$CINFO" | cut -d\  -f7)
  fi
}
config_if() {

# Uncomment to rename network interfaces
#  if [ $1 == "eth0" ]; then
#    ethname="eth1"
#  fi
#  if [ $1 == "eth1" ]; then
#    ethname="eth2"
#  fi

  echo "graph_order down up"
  echo "graph_title $ethname traffic"
  echo "graph_args --base 1000"
  echo "graph_vlabel bits in (-) / out (+) per \${graph_period}"
  echo "graph_category network"
  echo "graph_info This graph shows the traffic of the $INTERFACE network interface. Please note that the traffic is shown in bits per second, not bytes. IMPORTANT: Since the data source for this plugin use 32bit counters, this plugin is really unreliable and unsuitable for most 100Mb (or faster) interfaces, where bursts are expected to exceed 50Mbps. This means that this plugin is usuitable for most production environments. To avoid this problem, use the ip_ plugin instead."
  echo "down.label received"
  echo "down.type DERIVE"
  echo "down.min 0"
  echo "down.graph no"
  echo "down.cdef down,8,*"
  echo "up.label bps"
  echo "up.type DERIVE"
  echo "up.min 0"
  echo "up.negative down"
  echo "up.cdef up,8,*"
  if ethtool $1 | grep -q 'Speed: [0-9]\+'; then
    MAX=$(($(ethtool $1 | grep Speed | sed -e 's/[[:space:]]\{1,\}/ /g' -e 's/^ //' -e 's/M.*//' | cut -d\  -f2) * 1000000))
    echo "up.max $MAX"
    echo "down.max $MAX"
  fi
}
fetch_if() {
  IINFO=$(grep "$1:" /proc/net/dev | cut -d: -f2 | sed -e 's/  / /g')
  echo "down.value" $(echo $IINFO | cut -d\  -f1)
  echo "up.value" $(echo $IINFO | cut -d\  -f9)
}
config_if_err() {

# Uncomment to rename network interfaces
#  if [ $1 == "eth0" ]; then
#    ethname="eth1"
#  fi
#  if [ $1 == "eth1" ]; then
#    ethname="eth2"
#  fi

  echo "graph_order rcvd trans"
  echo "graph_title $ethname errors"
  echo "graph_args --base 1000"
  echo "graph_vlabel packets in (-) / out (+) per \${graph_period}"
  echo "graph_category network"
  echo "graph_info This graph shows the amount of errors on the $1 network interface."
  echo "rcvd.label packets"
  echo "rcvd.type COUNTER"
  echo "rcvd.graph no"
  echo "rcvd.warning 1"
  echo "trans.label packets"
  echo "trans.type COUNTER"
  echo "trans.negative rcvd"
  echo "trans.warning 1"
}
fetch_if_err() {
  IINFO=$(grep "$1:" /proc/net/dev | cut -d: -f2 | sed -e 's/  / /g')
  echo "rcvd.value" $(echo $IINFO | cut -d\  -f3)
  echo "trans.value" $(echo $IINFO | cut -d\  -f11)
}
config_load() {
  echo "graph_title Load average
graph_args --base 1000 -l 0
graph_vlabel load
graph_scale no
graph_category system
load.label load
load.warning 10
load.critical 120
graph_info The load average of the machine describes how many processes are in the run-queue (scheduled to run \"immediately\").
load.info Average load for the five minutes."
}
fetch_load() {
  echo "load.value" $(cut -f2 -d\  /proc/loadavg)
}
config_memory() {
  MINFO=$(cat /proc/meminfo | sed 's/ \{1,\}/ /g;')
  MEMTOTAL=$(echo "$MINFO" | grep "^MemTotal:" | cut -d\  -f2)
  PAGETABLES=$(echo "$MINFO" | grep "^PageTables:" | cut -d\  -f2)
  SWAPCACHED=$(echo "$MINFO" | grep "^SwapCached:" | cut -d\  -f2)
  SWAPTOTAL=$(echo "$MINFO" | grep "^SwapTotal:" | cut -d\  -f2)
  VMALLOCUSED=$(echo "$MINFO" | grep "^VmallocUsed:" | cut -d\  -f2)
  SLAB=$(echo "$MINFO" | grep "^Slab:" | cut -d\  -f2)
  MAPPED=$(echo "$MINFO" | grep "^Mapped:" | cut -d\  -f2)
  COMMITTEDAS=$(echo "$MINFO" | grep "^Committed_AS:" | cut -d\  -f2)
  ACTIVE=$(echo "$MINFO" | grep "^Active:" | cut -d\  -f2)
  INACTIVE=$(echo "$MINFO" | grep "^Inactive:" | cut -d\  -f2)
  ACTIVEANON=$(echo "$MINFO" | grep "^ActiveAnon:" | cut -d\  -f2)
  ACTIVECACHE=$(echo "$MINFO" | grep "^ActiveCache:" | cut -d\  -f2)
  INACTIVE=$(echo "$MINFO" | grep "^Inactive:" | cut -d\  -f2)
  INACTDIRTY=$(echo "$MINFO" | grep "^Inact_dirty:" | cut -d\  -f2)
  INACTLAUNDY=$(echo "$MINFO" | grep "^Inact_laundry:" | cut -d\  -f2)
  INACTCLEAN=$(echo "$MINFO" | grep "^Inact_clean:" | cut -d\  -f2)

  GRAPH_ORDER="apps";
  test "$PAGETABLES" != "" && GRAPH_ORDER="$GRAPH_ORDER page_tables"
  test "$SWAPCACHED" != "" && GRAPH_ORDER="$GRAPH_ORDER swap_cache"
  test "$VMALLOCUSED" != "" && GRAPH_ORDER="$GRAPH_ORDER vmalloc_used"
  test "$SLAB" != "" && GRAPH_ORDER="$GRAPH_ORDER slab"
  GRAPH_ORDER="$GRAPH_ORDER cached buffers free swap"

  echo "graph_args --base 1024 -l 0 --vertical-label Bytes --upper-limit $MEMTOTAL"
  echo "graph_title Memory usage"
  echo "graph_category system"
  echo "graph_info This graph shows what the machine uses its memory for."
  echo "graph_order $GRAPH_ORDER"
  echo "apps.label apps"
  echo "apps.draw AREA"
  echo "apps.info Memory used by user-space applications."
  echo "buffers.label buffers"
  echo "buffers.draw STACK"
  echo "buffers.info Block device (e.g. harddisk) cache. Also where \"dirty\" blocks are stored until written."
  echo "swap.label swap"
  echo "swap.draw STACK"
  echo "swap.info Swap space used."
  echo "cached.label cache"
  echo "cached.draw STACK"
  echo "cached.info Parked file data (file content) cache."
  echo "free.label unused"
  echo "free.draw STACK"
  echo "free.info Wasted memory. Memory that is not used for anything at all."
  if [ "$SLAB" != "" ]; then
    echo "slab.label slab_cache"
    echo "slab.draw STACK"
    echo "slab.info Memory used by the kernel (major users are caches like inode, dentry, etc)."
  fi
  if [ "$SWAPCACHED" != "" ]; then
    echo "swap_cache.label swap_cache"
    echo "swap_cache.draw STACK"
    echo "swap_cache.info A piece of memory that keeps track of pages that have been fetched from swap but not yet been modified."
  fi
  if [ "$PAGETABLES" != "" ]; then
    echo "page_tables.label page_tables"
    echo "page_tables.draw STACK"
    echo "page_tables.info Memory used to map between virtual and physical memory addresses.\n"
  fi
  if [ "$VMALLOCUSED" != "" ]; then
    echo "vmalloc_used.label vmalloc_used"
    echo "vmalloc_used.draw STACK"
    echo "vmalloc_used.info Virtual memory used by the kernel (used when the memory does not have to be physically contigious)."
  fi
  if [ "$COMMITTEDAS" != "" ]; then
    echo "committed.label committed"
    echo "committed.draw LINE2"
    echo "committed.warn" $(($SWAPTOTAL + $MEMTOTAL))
    echo "committed.info The amount of memory that would be used if all the memory that's been allocated were to be used."
  fi
  if [ "$MAPPED" != "" ]; then
    echo "mapped.label mapped"
    echo "mapped.draw LINE2"
    echo "mapped.info All mmap()ed pages."
  fi
  if [ "$ACTIVE" != "" ]; then
    echo "active.label active"
    echo "active.draw LINE2"
    echo "active.info Memory recently used. Not reclaimed unless absolutely necessary."
  fi
  if [ "$ACTIVEANON" != "" ]; then
    echo "active_anon.label active_anon"
    echo "active_anon.draw LINE1"
  fi
  if [ "$ACTIVECACHE" != "" ]; then
    echo "active_cache.label active_cache"
    echo "active_cache.draw LINE1"
  fi
  if [ "$INACTIVE" != "" ]; then
    echo "inactive.label inactive"
    echo "inactive.draw LINE2"
    echo "inactive.info Memory not currently used."
  fi
  if [ "$INACTDIRTY" != "" ]; then
    echo "inact_dirty.label inactive_dirty"
    echo "inact_dirty.draw LINE1"
    echo "inact_dirty.info Memory not currently used, but in need of being written to disk."
  fi
  if [ "$INACTLAUNDRY" != "" ]; then
    echo "inact_laundry.label inactive_laundry"
    echo "inact_laundry.draw LINE1"
  fi
  if [ "$INACTCLEAN" != "" ]; then
    echo "inact_clean.label inactive_clean"
    echo "inact_clean.draw LINE1"
    echo "inact_clean.info Memory not currently used."
  fi
}
fetch_memory() {
  MINFO=$(cat /proc/meminfo | sed 's/ \{1,\}/ /g;')
  MEMTOTAL=$(echo "$MINFO" | grep "^MemTotal:" | cut -d\  -f2)
  MEMFREE=$(echo "$MINFO" | grep "^MemFree:" | cut -d\  -f2)
  BUFFERS=$(echo "$MINFO" | grep "^Buffers:" | cut -d\  -f2)
  CACHED=$(echo "$MINFO" | grep "^Cached:" | cut -d\  -f2)
  SWAP_TOTAL=$(echo "$MINFO" | grep "^SwapTotal:" | cut -d\  -f2)
  SWAP_FREE=$(echo "$MINFO" | grep "^SwapFree:" | cut -d\  -f2)
  MEMTOTAL=$(echo "$MINFO" | grep "^MemTotal:" | cut -d\  -f2)
  PAGETABLES=$(echo "$MINFO" | grep "^PageTables:" | cut -d\  -f2)
  SWAPCACHED=$(echo "$MINFO" | grep "^SwapCached:" | cut -d\  -f2)
  VMALLOCUSED=$(echo "$MINFO" | grep "^VmallocUsed:" | cut -d\  -f2)
  SLAB=$(echo "$MINFO" | grep "^Slab:" | cut -d\  -f2)
  MAPPED=$(echo "$MINFO" | grep "^Mapped:" | cut -d\  -f2)
  COMMITTEDAS=$(echo "$MINFO" | grep "^Committed_AS:" | cut -d\  -f2)
  ACTIVE=$(echo "$MINFO" | grep "^Active:" | cut -d\  -f2)
  INACTIVE=$(echo "$MINFO" | grep "^Inactive:" | cut -d\  -f2)
  ACTIVEANON=$(echo "$MINFO" | grep "^ActiveAnon:" | cut -d\  -f2)
  ACTIVECACHE=$(echo "$MINFO" | grep "^ActiveCache:" | cut -d\  -f2)
  INACTIVE=$(echo "$MINFO" | grep "^Inactive:" | cut -d\  -f2)
  INACTDIRTY=$(echo "$MINFO" | grep "^Inact_dirty:" | cut -d\  -f2)
  INACTLAUNDY=$(echo "$MINFO" | grep "^Inact_laundry:" | cut -d\  -f2)
  INACTCLEAN=$(echo "$MINFO" | grep "^Inact_clean:" | cut -d\  -f2)
  APPS=$(($MEMTOTAL - $MEMFREE - $BUFFERS - $CACHED))
  SWAP=$(($SWAP_TOTAL - $SWAP_FREE))
  echo "buffers.value" $(($BUFFERS * 1024))
  echo "swap.value" $(($SWAP * 1024))
  echo "cached.value" $(($CACHED * 1024))
  echo "free.value" $(($MEMFREE * 1024))
  if [ "$SLAB" != "" ]; then
    echo "slab.value" $(($SLAB * 1024))
    APPS=$(($APPS - $SLAB))
  fi
  if [ "$SWAPCACHED" != "" ]; then
    echo "swap_cache.value" $(($SWAPCACHED * 1024))
    APPS=$(($APPS - $SWAPCACHED))
  fi
  if [ "$PAGETABLES" != "" ]; then
    echo "page_tables.value" $(($PAGETABLES * 1024))
    APPS=$(($APPS - $PAGETABLES))
  fi
  if [ "$VMALLOCUSED" != "" ]; then
    echo "vmalloc_used.value" $(($VMALLOCUSED * 1024))
    APPS=$(($APPS - $VMALLOCUSED))
  fi
  if [ "$COMMITTEDAS" != "" ]; then
    echo "committed.value" $(($COMMITTEDAS * 1024))
  fi
  if [ "$MAPPED" != "" ]; then
    echo "mapped.value" $(($MAPPED * 1024))
  fi
  if [ "$ACTIVE" != "" ]; then
    echo "active.value" $(($ACTIVE * 1024))
  fi
  if [ "$ACTIVEANON" != "" ]; then
    echo "active_anon.value" $(($ACTIVEANON * 1024))
  fi
  if [ "$ACTIVECACHE" != "" ]; then
    echo "active_cache.value" $(($ACTIVECACHE * 1024))
  fi
  if [ "$INACTIVE" != "" ]; then
    echo "inactive.value" $(($INACTIVE * 1024))
  fi
  if [ "$INACTDIRTY" != "" ]; then
    echo "inact_dirty.value" $(($INACTDIRTY * 1024))
  fi
  if [ "$INACTLAUNDRY" != "" ]; then
    echo "inact_laundry.value" $(($INACTLAUNDRY * 1024))
  fi
  if [ "$INACTCLEAN" != "" ]; then
    echo "inact_clean.value" $(($INACTCLEAN * 1024))
  fi

  echo "apps.value" $(($APPS * 1024))
}
config_processes() {
  echo "graph_title Processes"
  echo "graph_args --base 1000 -l 0 "
  echo "graph_vlabel number of processes"
  echo "graph_category processes"
  echo "graph_info This graph shows the number of processes in the system."
  echo "processes.label processes"
  echo "processes.draw LINE2"
  echo "processes.info The current number of processes."
}
fetch_processes() {
  echo "processes.value" $(echo /proc/[0-9]* | wc -w)
}
config_swap() {
  echo "graph_title Swap in/out"
  echo "graph_args -l 0 --base 1000"
  echo "graph_vlabel pages per \${graph_period} in (-) / out (+)"
  echo "graph_category system"
  echo "swap_in.label swap"
  echo "swap_in.type DERIVE"
  echo "swap_in.max 100000"
  echo "swap_in.min 0"
  echo "swap_in.graph no"
  echo "swap_out.label swap"
  echo "swap_out.type DERIVE"
  echo "swap_out.max 100000"
  echo "swap_out.min 0"
  echo "swap_out.negative swap_in"
}
fetch_swap() {
  if [ -f /proc/vmstat ]; then
    SINFO=$(cat /proc/vmstat)
    echo "swap_in.value" $(echo "$SINFO" | grep "^pswpin" | cut -d\  -f2)
    echo "swap_out.value" $(echo "$SINFO" | grep "^pswpout" | cut -d\  -f2)
  else
    SINFO=$(grep "^swap" /proc/stat)
    echo "swap_in.value" $(echo "$SINFO" | cut -d\  -f2)
    echo "swap_out.value" $(echo "$SINFO" | cut -d\  -f3)
  fi
}
config_netstat() {
  echo "graph_title Netstat"
  echo "graph_args -l 0 --base 1000"
  echo "graph_vlabel active connections"
  echo "graph_category network"
  echo "graph_period second"
  echo "graph_info This graph shows the TCP activity of all the network interfaces combined."
  echo "active.label active"
  echo "active.type DERIVE"
  echo "active.max 50000"
  echo "active.min 0"
  echo "active.info The number of active TCP openings per second."
  echo "passive.label passive"
  echo "passive.type DERIVE"
  echo "passive.max 50000"
  echo "passive.min 0"
  echo "passive.info The number of passive TCP openings per second."
  echo "failed.label failed"
  echo "failed.type DERIVE"
  echo "failed.max 50000"
  echo "failed.min 0"
  echo "failed.info The number of failed TCP connection attempts per second."
  echo "resets.label resets"
  echo "resets.type DERIVE"
  echo "resets.max 50000"
  echo "resets.min 0"
  echo "resets.info The number of TCP connection resets."
  echo "established.label established"
  echo "established.type GAUGE"
  echo "established.max 50000"
  echo "established.info The number of currently open connections."
}
fetch_netstat() {
  NINFO=$(netstat -s | sed 's/ \{1,\}/ /g')
  echo "active.value" $(echo "$NINFO" | grep "active connections" | cut -d\  -f2)
  echo "passive.value" $(echo "$NINFO" | grep "passive connection" | cut -d\  -f2)
  echo "failed.value" $(echo "$NINFO" | grep "failed connection" | cut -d\  -f2)
  echo "resets.value" $(echo "$NINFO" | grep "connection resets" | cut -d\  -f2)
  echo "established.value" $(echo "$NINFO" | grep "connections established" | cut -d\  -f2)
}
config_uptime() {
  echo "graph_title Uptime"
  echo "graph_args --base 1000 -l 0 "
  echo "graph_category system"
  echo "graph_vlabel uptime in days"
  echo "uptime.label uptime"
  echo "uptime.draw AREA"
  echo "uptime.cdef uptime,86400,/"
}
fetch_uptime() {
  echo "uptime.value" $(cut -d\  -f1 /proc/uptime)
}
config_interrupts() {
  echo "graph_title Interrupts & context switches"
  echo "graph_args --base 1000 -l 0"
  echo "graph_vlabel interrupts & ctx switches / \${graph_period}"
  echo "graph_category system"
  echo "graph_info This graph shows the number of interrupts and context switches on the system. These are typically high on a busy system."
  echo "intr.info Interrupts are events that alter sequence of instructions executed by a processor. They can come from either hardware (exceptions, NMI, IRQ) or software."
  echo "ctx.info A context switch occurs when a multitasking operatings system suspends the currently running process, and starts executing another."
  echo "intr.label interrupts"
  echo "ctx.label context switches"
  echo "intr.type DERIVE"
  echo "ctx.type DERIVE"
  echo "intr.max 100000"
  echo "ctx.max 100000"
  echo "intr.min 0"
  echo "ctx.min 0"
}
fetch_interrupts() {
  IINFO=$(cat /proc/stat)
  echo "ctx.value" $(echo "$IINFO" | grep "^ctxt" | cut -d\  -f2)
  echo "intr.value" $(echo "$IINFO" | grep "^intr" | cut -d\  -f2)
}
config_irqstats() {
  echo "graph_title Individual interrupts
graph_args --base 1000 -l 0;
graph_vlabel interrupts / \${graph_period}
graph_category system"
  CPUS=$(grep 'CPU[0-9]' /proc/interrupts | wc -w)
  IINFO=$(sed -e 's/ \{1,\}/ /g' -e 's/^ //' /proc/interrupts  | grep '.:')
  for ID in $(echo "$IINFO" | cut -d: -f1)
  do
    IDL=$(echo "$IINFO" | grep "^$ID:")
    INFO=$(eval "echo \"$IDL\" | cut -d\  -f$((3+$CPUS))-")
    if [ "$INFO" = "" ]; then
      echo "i$ID.label $ID"
    else
      echo "i$ID.label $INFO"
      echo "i$ID.info Interrupt $ID, for device(s): $INFO"
    fi
    echo "i$ID.type DERIVE"
    echo "i$ID.min 0"
  done
}
fetch_irqstats() {
  CPUS=$(grep 'CPU[0-9]' /proc/interrupts | wc -w)
  IINFO=$(sed -e 's/ \{1,\}/ /g' -e 's/^ //' /proc/interrupts  | grep '.:')
  for ID in $(echo "$IINFO" | cut -d: -f1)
  do
    IDL=$(echo "$IINFO" | grep "^$ID:")
    VALS=$(eval "echo \"$IDL\" | cut -d\  -f2-$((1+$CPUS))")
    VALUE=0
    for VAL in $VALS;
    do
      VALUE=$(($VALUE + $VAL))
    done
    echo "i$ID.value $VALUE"
  done
}
config_ntpdate() {
  echo "graph_title NTP offset and dealy to peer $NTP_PEER"
  echo "graph_args --base 1000 --vertical-label msec"
  echo "offset.label Offset"
  echo "offset.draw LINE2"
  echo "delay.label Delay"
  echo "delay.draw LINE2"
}

fetch_ntpdate() {
  NTPDATE="/usr/sbin/ntpdate"
  OFFSET=0
  DELAY=0
  if [ "$NTP_PEER" != "" ]; then
    if [ -x "$NTPDATE" ]; then
      DATA=$($NTPDATE -q $NTP_PEER | awk '/^server.*offset/{gsub(/,/,"");printf "%s %s", ($6*1000), ($8*1000);}')
      OFFSET=$(echo "$DATA" | cut -d\  -f1)
      DELAY=$(echo "$DATA" | cut -d\  -f2)
    fi
  fi
  echo "offset.value $OFFSET"
  echo "delay.value $DELAY"
}

config_users() {
    echo "graph_title Logged in users"
    echo "graph_args --base 1000 -l 0"
    echo "graph_vlabel Users"
    echo "graph_scale no"
    echo "graph_category system"
    echo "graph_printf %3.0lf"
    echo "pts.label pts"
    echo "pts.draw AREASTACK"
    echo "pts.colour 00FFFF"
}

fetch_users() {
    pts=$(ps aux | grep pts | wc | awk '{print $1-1}')
    if [ $pts -lt 0 ]; then
  pts=0
    fi
    echo "pts.value $pts"
}

config_ipmi_temp() {
    echo "graph_title Machine temperature based on IPMI"
    echo "graph_vlabel Degrees celcius"
    echo "graph_category Sensors"
    echo "SystemTemp.label System Temp"
    echo "SystemTemp.critical 0:65.000"
    echo "SystemTemp.warning 0:57.000"
}

fetch_ipmi_temp() {
    cputemp=$(cat /proc/tsinfo/systemp)
    echo "SystemTemp.value $cputemp"
}

config_hdd_temp() {
    echo "graph_title Fan speeds based on IPMI"
    echo "graph_vlabel Celsius"
    echo "graph_category Sensors"

    number_of_drives=$(find /sys/block/sd* -name "sd[a-z]" -print | wc -l)

    i=1
    while [ $i -le $number_of_drives ]
    do
  echo "HDD$i.label HDD Temp $i"
  echo "HDD$i.warning 60"
  i=`expr $i + 1`
    done
}

fetch_hdd_temp() {

    number_of_drives=$(find /sys/block/sd* -name "sd[a-z]" -print | wc -l)

    i=1
    while [ $i -le $number_of_drives ]
    do
  hddtemp=$(/sbin/get_hd_temp $i)
  echo "HDD$i.value $hddtemp"
  i=`expr $i + 1`
    done
}

# ===== NODE CODE =====
do_list() {
  echo $PLUGINS
}


do_nodes() {
  echo "$HOSTNAME"
  echo "."
}

do_config() {
  if echo "$PLUGINS" | grep "\b$1\b" >/dev/null 2>&1; then
    config_$1
  else
    echo "# Unknown service"
  fi
  echo "."
}

do_fetch() {
  if echo "$PLUGINS" | grep "\b$1\b" >/dev/null 2>&1; then
    fetch_$1
  else
    echo "# Unknown service"
  fi
  echo "."
}

do_version() {
  echo "munins node on $HOSTNAME version: $VERSION (munin-lite)"
}

do_quit() {
  exit 0
}

# ===== Runtime config =====
RES=""
for PLUG in $PLUGINS
do
  if [ "$PLUG" = "if_" ]; then
    for INTER in $(grep '^ *\(ppp\|eth\|wlan\|ath\|ra\|ipsec\)\([^:]\)\{1,\}:' /proc/net/dev | cut -f1 -d: | sed 's/ //g');
    do
      INTERRES=$(echo $INTER | sed 's/\./VLAN/')
      RES="$RES if_$INTERRES"
      eval "fetch_if_${INTERRES}() { fetch_if $INTER $@; };"
      eval "config_if_${INTERRES}() { config_if $INTER $@; };"
    done
  elif [ "$PLUG" = "if_err_" ]; then
    for INTER in $(grep '^ *\(ppp\|eth\|wlan\|ath\|ra\|ipsec\)\([^:]\)\{1,\}:' /proc/net/dev | cut -f1 -d: | sed 's/ //g');
    do
      INTERRES=$(echo $INTER | sed 's/\./VLAN/')
      RES="$RES if_err_$INTERRES"
      eval "fetch_if_err_${INTERRES}() { fetch_if_err $INTER $@; };"
      eval "config_if_err_${INTERRES}() { config_if_err $INTER $@; };"
    done
  elif [ "$PLUG" = "netstat" ]; then
    if netstat -s >/dev/null 2>&1; then
      RES="$RES netstat"
    fi
  elif [ "$PLUG" = "plugindir_" ]; then
    for MYPLUGIN in $(ls -1 $PLUGINPATTERN 2>/dev/null );
    do
      if [ -f $MYPLUGIN -a -x $MYPLUGIN ]; then
        MYPLUGINNAME=$(basename $MYPLUGIN)
        #ensure we don't have name collision
        if echo "$RES" | grep "\b$MYPLUGINNAME\b" >/dev/null 2>&1 ; then
          MYPLUGINNAME="plugindir_$MYPLUGINNAME"
        fi
        RES="$RES $MYPLUGINNAME"
        eval "fetch_${MYPLUGINNAME}() { $MYPLUGIN ; };"
        eval "config_${MYPLUGINNAME}() { $MYPLUGIN config ; };"
      fi
    done
  else
    RES="$RES $PLUG";
  fi
done
PLUGINS=$RES

# ===== MAIN LOOP =====
FUNCTIONS="list nodes config fetch version quit"
HOSTNAME=$(hostname -f 2>/dev/null || hostname)
echo "# munin node at $HOSTNAME"
while read arg0 arg1
do
  arg0=$(echo "$arg0" | xargs)
  arg1=$(echo "$arg1" | xargs)
  if ! echo "$FUNCTIONS" | grep "\b$arg0\b" >/dev/null 2>&1 ; then
    echo "# Unknown command. Try" $(echo "$FUNCTIONS" | sed -e 's/\( [[:alpha:]]\{1,\}\)/,\1/g' -e 's/,\( [[:alpha:]]\{1,\}\)$/ or\1/')
    continue
  fi

  do_$arg0 $arg1
done
