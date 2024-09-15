#!/bin/bash
#	binfmt-manager
#	A script to manage binfmt entries
#	SPDX-License-Identifier: MIT
#	Copyright (c) 2024 eweOS developers.

readonly PROGNAME=$(basename $0)
readonly PROGDIR=$(readlink $(dirname $0))
readonly ARGS="$@"

readonly binfm_pfx="/proc/sys/fs/binfmt_misc"
readonly binfm_confdir="/etc/binfmt.d"
readonly binfm_mod="binfmt_misc"

die() {
	echo "$1" 1>&2

	exit 1
}

dbg() {
	[ "$DEBUG" ] && echo "$@"
}

usage() {
	cat <<EOF
Usage: $PROGNAME command [args,]

Manage binfmt_misc entries

COMMANDS:
	list			list binfmts enabled in kernel
	register <binfmt|file>	register binfmt with the kernel
	unregister <binfmt>	unregister given binfmt with the kernel
	unregister-all		unregister all binfmts with the kernel
	enable <binfmt>		enable given binfmt with the kernel
	disable <binfmt>	disable given binfmt with the kernel
	reload			reload all configured binfmts
	help			show this help text
EOF
}

check_perm() {
	[ "$EUID" = 0 ] || die "This script must be run with root privileges"
}

prepare_fs() {
	modprobe "$binfm_mod"
	mountpoint -q "$binfm_pfx" || \
		mount -t binfmt_misc binfmt "$binfm_pfx" || \
		die "Cannot mount binfmtfs"
}

cmdline() {
	local comm=$1
	shift

	case "$comm" in
		register)
			check_perm
			prepare_fs
			register_dispatch "$@"
			;;
		unregister)
			check_perm
			prepare_fs
			_toggle -1 "$@"
			;;
		unregister-all)
			check_perm
			prepare_fs
			_unregister_all
			;;
		enable)
			check_perm
			prepare_fs
			_toggle 1 "$@"
			;;
		disable)
			check_perm
			prepare_fs
			_toggle 0 "$@"
			;;
		reload)
			check_perm
			prepare_fs
			_reload
			;;
		list)
			_list
			;;
		help|*)
			usage
			exit 0
			;;
	esac
}

register_dispatch() {
	local item="$1"

	[ "$item" ] || die "No binfmt name or file path provided"

	if [ -f "$item" ]; then
		_register "$item"
	else
		_register "$binfm_confdir/$item"
	fi
}

_list() {
	if [ ! -f "$binfm_pfx"/status ]; then
		echo "binfmt is not enabled"
		exit 0
	fi

	for files in "$binfm_pfx"/*; do
		[ "$files" = $binfm_pfx/register ] && continue
		[ "$files" = $binfm_pfx/status ]   && continue
		echo $(basename "$files"):
		echo -e "\t" Status: $(cat "$files" | sed -n '1p')
		echo -e "\t" Interpreter: \
			$(cat "$files" | sed -n '2p' | cut -f 2 -d ' ')
		echo -e "\t" Flags: \
			$(cat "$files" | sed -n '3p' | cut -f 2 -d ' ')
	done
}

_reload() {
	_unregister_all

	[ -d "$binfm_confdir" ] || return 0

	for cfg in $(ls "$binfm_confdir"); do
		[ -f "$binfm_confdir/$cfg" ] || continue
		dbg "Registering $binfm_confdir/$cfg"
		_register "$binfm_confdir/$cfg"
	done
}

_field() {
	local v="$(grep -e "^$2:" "$1" | tail -n 1 |\
		   sed -e "s/$2:[[:space:]]*//")"
	[ "$v" ] || die "$1: variable $2 is not set"
	echo "$v"
}

_hex() {
	printf '%s\n' "$1" | sed -E 's/(..)/\\x\1/g'
}

_register() {
	[ -f "$1" ] || die "binfmt $1 does not exist"

	local name="$(_field "$1" name)"
	local type="$(_field "$1" type)"
	local offset="$(_field "$1" offset)"
	local magic="$(_field "$1" magic)"
	local mask="$(_field "$1" mask)"
	local interpreter="$(_field "$1" interpreter)"
	local flags="$(_field "$1" flags)"

	([ "$name" ] && [ "$type" ] && [ "$offset" ] && [ "$magic" ] &&
	 [ "$mask" ] && [ "interpreter" ] && [ "flags" ]) ||
		exit 1

	[ -f "$binfm_pfx/$name" ] && die "binfmt named '$name' already exists"

	magic="$(_hex "$magic")"
	mask="$(_hex "$mask")"
	echo -n ":${name}:${type}:${offset}:${magic}:${mask}:${interpreter}:${flags}" > $binfm_pfx/register
}

_toggle() {
	local flag="$1"
	local item="$2"

	[ "$item" ] || die "No binfmt provided"

	if [[ -f "$binfm_pfx/$item" ]]; then
		echo $flag > "$binfm_pfx/$item" 2>/dev/null
	else
		die "binfmt '$item' was not registered"
	fi
}

_unregister_all() {
	for files in $binfm_pfx/*; do
		[ "$files" = $binfm_pfx/register ] && continue
		[ "$files" = $binfm_pfx/status ]   && continue
		_toggle -1 "$(basename $files)"
	done
}

cmdline $ARGS
