#!/bin/sh
# shellcheck disable=SC2015
set -e

readonly PKG_NAME='remote-agent'

STATE_DIR="/etc/remote-agent"
CRED_JSON="$STATE_DIR/credentials.json"
ADOPTED_FLAG="$STATE_DIR/adopted.ok"
EXT_DIR="/usr/libexec/rpcd/provision.d"
ADOPT_TOKEN_FILE="$STATE_DIR/adoption.token"
DISCOVERABLE_FLAG="$STATE_DIR/discoverable.on"

RPC_USER="remote_agent"
STATE_DIR="/etc/remote-agent"
CRED_JSON="$STATE_DIR/credentials.json"
# shellcheck disable=SC2034
ADOPTED_FLAG="$STATE_DIR/adopted.ok"

# shellcheck disable=SC1091
. /lib/functions.sh

is_installed() { command -v "$1" >/dev/null 2>&1; }
read_stdin() { REQ="$(cat)"; }
jget() { jsonfilter -s "$REQ" -e "$1" 2>/dev/null; }
jarr() { jsonfilter -s "$REQ" -e "$1[*]" 2>/dev/null; }
jout() { printf '%s\n' "$1"; }
ok()   { jout '{"ok":true}'; }
err()  { jout "{\"ok\":false,\"error\":$(printf '%s' "$1" | sed 's/\"/\\\\\"/g; s/^/\"/; s/$/\"/') }"; }

do_load_options() {
	config_load "$PKG_NAME"
	config_get controller_url "$PKG_NAME" controller_url
	config_get poll_interval "$PKG_NAME" poll_interval '300'
}

core_list() {
	cat <<'JSON'
{
	"ping": {},
	"reboot": { "delay": "int" },
	"passwd": { "user": "str", "password": "str" },
	"uci": { "commands": ["str"] },
	"service": { "name": "str", "action": "str" },
	"wifi": { "action": "str" },
	"pkg": { "action": "str", "names": ["str"] },
	"bootstrap_info": {},
	"adopt": { "adoption_token": "str", "new_password": "str" }
}
JSON
}

do_passwd() {
	u="$(jget '@.user')"; p="$(jget '@.password')"
	[ -n "$u" ] && [ -n "$p" ] || { err "missing user/password"; return; }
	if is_installed chpasswd; then
		printf '%s:%s\n' "$u" "$p" | chpasswd && ok || err "chpasswd failed"
	else
		(echo "$p"; echo "$p") | passwd "$u" >/dev/null 2>&1 && ok || err "passwd failed"
	fi
}

do_uci() {
	cmds="$(jarr '@.commands')"
	[ -n "$cmds" ] || { err "no commands"; return; }
	rc=0
	echo "$cmds" | while IFS= read -r line; do
		set -- $line
		case "$1" in set|add|delete|rename|reorder|commit|changes|revert)
			uci "$@" || rc=1
			;;
		*) rc=2 ;;
		esac
	done
	[ "$rc" -eq 0 ] && ok || err "uci error/denied"
}

do_service() {
	name="$(jget '@.name')"; action="$(jget '@.action')"
	[ -n "$name" ] && [ -n "$action" ] || { err "name/action required"; return; }
	case "$action" in start|stop|restart|reload|enable|disable|status)
		/etc/init.d/"$name" "$action" >/dev/null 2>&1 && ok || err "service $action failed"
		;;
	*) err "invalid action" ;;
	esac
}

do_wifi() {
	act="$(jget '@.action')"
	case "$act" in reload|up|down)
		wifi "$act" >/dev/null 2>&1 && ok || err "wifi $act failed"
		;;
	*) err "invalid action" ;;
	esac
}

do_reboot() {
	d="$(jget '@.delay')"; d="${d:-0}"
	( sleep "$d"; /sbin/reboot ) >/dev/null 2>&1 &
	jout '{ "ok": true, "scheduled": true }'
}

pkg_driver() {
	if is_installed apk; then echo apk; elif is_installed opkg; then echo opkg; else echo none; fi
}
do_pkg() {
	act="$(jget '@.action')"
	names="$(jarr '@.names')"
	drv="$(pkg_driver)"
	[ "$drv" = none ] && { err "no package manager"; return; }

case "${drv}:${act}" in
		apk:update) apk update >/dev/null 2>&1 && ok || err "apk update failed" ;;
		apk:install) [ -n "$names" ] || { err "no names"; return; }
								 echo "$names" | xargs -r apk add >/dev/null 2>&1 && ok || err "apk add failed" ;;
		apk:remove)  [ -n "$names" ] || { err "no names"; return; }
								 echo "$names" | xargs -r apk del >/dev/null 2>&1 && ok || err "apk del failed" ;;
		opkg:update) opkg update >/dev/null 2>&1 && ok || err "opkg update failed" ;;
		opkg:install) [ -n "$names" ] || { err "no names"; return; }
									echo "$names" | xargs -r opkg install >/dev/null 2>&1 && ok || err "opkg install failed" ;;
		opkg:remove)  [ -n "$names" ] || { err "no names"; return; }
									echo "$names" | xargs -r opkg remove >/dev/null 2>&1 && ok || err "opkg remove failed" ;;
		*) err "unsupported action" ;;
	esac
}

do_bootstrap_info() {
	if [ -f "$ADOPTED_FLAG" ] && [ ! -s "$CRED_JSON" ]; then err "adopted"; return; fi
	if [ ! -s "$CRED_JSON" ]; then err "no bootstrap credentials"; return; fi
	user="$(jsonfilter -s "$(cat "$CRED_JSON")" -e '@.username')"
	pass="$(jsonfilter -s "$(cat "$CRED_JSON")" -e '@.password')"
	host="$(uci -q get system.@system[0].hostname || echo openwrt)"
	board="$(jsonfilter -i /etc/board.json -e '@.model.id' 2>/dev/null || cat /tmp/sysinfo/board_name 2>/dev/null)"
	mac="$(ip link show br-lan 2>/dev/null | awk '/link\\/ether/{print $2}' || ip link show eth0 2>/dev/null | awk '/link\\/ether/{print $2}')"
	disc="$([ -f "$DISCOVERABLE_FLAG" ] && echo true || echo false)"
	printf '{"ok":true,"username":"%s","password":"%s","hostname":"%s","board":"%s","mac":"%s","discoverable":%s}\n' \
		"$user" "$pass" "$host" "$board" "$mac" "$disc"
}

rotate_to_shadow() {
	RPC_USER="remote_agent"
	newpass="$1"
	[ -n "$newpass" ] || { err "new_password required"; return 1; }
	if is_installed chpasswd; then
		printf '%s:%s\n' "$RPC_USER" "$newpass" | chpasswd
	else
		(echo "$newpass"; echo "$newpass") | passwd "$RPC_USER" >/dev/null
	fi
	# Point rpcd login at shadow: literal $p$USERNAME
	idx="$(uci -q show rpcd | awk -F'[][]' '/^rpcd\\.@login\\[[0-9]+\\]\\.username=remote_agent$/{print $2; exit}')"
	if [ -n "$idx" ]; then
# shellcheck disable=SC2016
		uci set rpcd.@login["$idx"].password='$p$remote_agent'
		uci commit rpcd
	fi
	/etc/init.d/rpcd restart >/dev/null 2>&1 || true
	shred -u "$CRED_JSON" 2>/dev/null || rm -f "$CRED_JSON"
	: > "$ADOPTED_FLAG"
	rm -f "$DISCOVERABLE_FLAG"
	ubus -S call umdns unregister '{"name":"_owrt-prov._tcp"}' >/dev/null 2>&1 || true
	ok
}

do_adopt() {
	token="$(jget '@.adoption_token')"
	newpass="$(jget '@.new_password')"
	[ -n "$token" ] && [ -n "$newpass" ] || { err "adoption_token and new_password required"; return; }
	[ -f "$DISCOVERABLE_FLAG" ] || { err "not discoverable"; return; }
	expect="$(cat "$ADOPT_TOKEN_FILE" 2>/dev/null)"
	[ -n "$expect" ] || { err "no token on device"; return; }
	[ "$token" = "$expect" ] || { err "token mismatch"; return; }
	rotate_to_shadow "$newpass"
}

ext_list() {
	[ -d "$EXT_DIR" ] || return
	for s in "$EXT_DIR"/*; do [ -x "$s" ] || continue; "$s" list || true; done
}
ext_call() {
	method="$1"
	[ -d "$EXT_DIR" ] || return 1
	for s in "$EXT_DIR"/*; do
		[ -x "$s" ] || continue
		if "$s" can "$method" >/dev/null 2>&1; then
			"$s" call "$method" <<EOF
$REQ
EOF
			return $?
		fi
	done
	return 1
}


STATE_DIR="/etc/remote-agent"
CRED_JSON="$STATE_DIR/credentials.json"
ADOPTED_FLAG="$STATE_DIR/adopted.ok"
DISCOVERABLE_FLAG="$STATE_DIR/discoverable.on"
ADOPT_TOKEN_FILE="$STATE_DIR/adoption.token"

discover_url_from_config() {
	uci -q get remote_agent.controller_url
}

discover_url_from_dhcp114() {
	[ -r "$STATE_DIR/dhcp114.url" ] && cat "$STATE_DIR/dhcp114.url"
}

controller_url() {
	url="$(discover_url_from_config)"
	[ -n "$url" ] && { echo "$url"; return; }
	url="$(discover_url_from_dhcp114)"
	[ -n "$url" ] && { echo "$url"; return; }
	echo ""
}

payload() {
	host="$(uci -q get system.@system[0].hostname || echo openwrt)"
	board="$(jsonfilter -i /etc/board.json -e '@.model.id' 2>/dev/null || cat /tmp/sysinfo/board_name 2>/dev/null)"
	mac="$(ip link show br-lan 2>/dev/null | awk '/link\/ether/{print $2}' || ip link show eth0 2>/dev/null | awk '/link\/ether/{print $2}')"
	ip="$(ip -4 addr show br-lan 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)"
	[ -z "$ip" ] && ip="$(ip -4 addr show eth0 2>/dev/null | awk '/inet /{print $2}' | cut -d/ -f1 | head -n1)"
	if [ -r "$CRED_JSON" ]; then
		user="$(jsonfilter -s "$(cat "$CRED_JSON")" -e '@.username')"
		pass="$(jsonfilter -s "$(cat "$CRED_JSON")" -e '@.password')"
	fi
	cat <<EOF
{"hostname":"$host","board":"$board","mac":"$mac","ip":"$ip","username":"$user","password":"$pass","ubus_path":"/ubus"}
EOF
}

post_json() {
	url="$1"; data="$2"; ca="$(uci -q get remote_agent.ca || echo /etc/ssl/certs/ca-certificates.crt)"
	if command -v uclient-fetch >/dev/null; then
		printf '%s' "$data" | uclient-fetch -q -T 30 -O - --post-data - --ca-certificate "$ca" "$url"
	else
		curl --fail --silent --show-error --max-time 30 --cacert "$ca" -H 'Content-Type: application/json' -d "$data" "$url"
	fi
}

enable_discoverable() {
	: > "$DISCOVERABLE_FLAG"
	token="$(cat "$ADOPT_TOKEN_FILE" 2>/dev/null)"
	host="$(uci -q get system.@system[0].hostname || echo openwrt)"
	port="$(uci -q get uhttpd.main.listen_https | sed 's/.*://;t;d')"
	[ -n "$port" ] || port="80"
	/etc/init.d/umdns start >/dev/null 2>&1 || true
	ubus -S call umdns register "$(printf '{"name":"_owrt-prov._tcp","port":%s,"txt":["host=%s","user=remote_agent","path=/ubus","adopt=1","token=%s"]}' "$port" "$host" "$token")" >/dev/null 2>&1 || true
	logger -t remote-agent "Discoverable mode enabled; mDNS (_owrt-prov._tcp)"
}

rotate_to_shadow_local() {
	RESP="$1"
	newpass="$(jsonfilter -s "$RESP" -e '@.new_password' 2>/dev/null)"
	[ -z "$newpass" ] && return 0
	token="$(cat "$ADOPT_TOKEN_FILE" 2>/dev/null)"
	[ -z "$token" ] && token="local"
	ubus call remote-agent adopt "$(printf '{"adoption_token":"%s","new_password":"%s"}' "$token" "$newpass")" >/dev/null 2>&1 || true
}

wait_for_net() {
# shellcheck disable=SC2034
	for i in $(seq 1 20); do ping -c1 -W1 1.1.1.1 >/dev/null 2>&1 && return 0 || sleep 3; done
	return 0
}
