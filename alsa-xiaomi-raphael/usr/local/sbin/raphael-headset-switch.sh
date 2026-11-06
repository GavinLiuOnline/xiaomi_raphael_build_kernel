#!/bin/bash
# Switch PipeWire default sink/source and WCD934x routing on 3.5mm jack events.
#
# Outputs (ALSA PCM nodes exposed by PipeWire):
#   Speaker   -> hw:0,1 (TFA9874, QUAT_MI2S)
#   Headphone -> hw:0,0 (WCD934x HPHL/HPHR over SLIMBUS)
#   Earpiece  -> hw:0,0 (WCD934x EAR over SLIMBUS, see raphael-audio)
#
# Inputs (both on the capture-only front-end, hw:0,2):
#   Internal mic -> AMIC1/ADC1
#   Headset mic  -> AMIC2/ADC2 (selected while a jack is plugged in)
set -uo pipefail

SPK_NODE="alsa_output.platform-sound.playback.1.0"
HP_NODE="alsa_output.platform-sound.playback.0.0"

jack_plugged() {
	amixer -c 0 cget numid=94 2>/dev/null | grep -q "values=on"
}

# Common Q6 routing mixers. They are reset by DAPM whenever the DSP ports are
# torn down, so they must be re-applied before every stream start.
q6_routing_on() {
	amixer -c 0 cset name='AIF1_CAP Mixer SLIM TX0' 1 >/dev/null 2>&1 || true
	amixer -c 0 cset name='MultiMedia3 Mixer SLIMBUS_0_TX' 1 >/dev/null 2>&1 || true
}

enable_internal_mic() {
	amixer -c 0 cset name='ADC MUX0' AMIC >/dev/null 2>&1 || true
	amixer -c 0 cset name='AMIC MUX0' ADC1 >/dev/null 2>&1 || true
	amixer -c 0 cset name='ADC1 Volume' 20 >/dev/null 2>&1 || true
	amixer -c 0 cset name='CDC_IF TX0 MUX' DEC0 >/dev/null 2>&1 || true
	amixer -c 0 cset name='DEC0 Volume' 84 >/dev/null 2>&1 || true
	q6_routing_on
}

enable_headset_mic() {
	# AMIC2 (jack mic) -> ADC2 -> DEC0 -> SLIM TX0
	amixer -c 0 cset name='ADC MUX1' AMIC >/dev/null 2>&1 || true
	amixer -c 0 cset name='AMIC MUX0' ADC2 >/dev/null 2>&1 || true
	amixer -c 0 cset name='ADC2 Volume' 20 >/dev/null 2>&1 || true
	amixer -c 0 cset name='CDC_IF TX0 MUX' DEC0 >/dev/null 2>&1 || true
	amixer -c 0 cset name='DEC0 Volume' 84 >/dev/null 2>&1 || true
	q6_routing_on
}

enable_headphone_path() {
	amixer -c 0 cset name='SLIM RX0 MUX' 'AIF1_PB' >/dev/null 2>&1 || true
	amixer -c 0 cset name='SLIM RX1 MUX' 'AIF1_PB' >/dev/null 2>&1 || true
	amixer -c 0 cset name='RX INT1_1 MIX1 INP0' 'RX0' >/dev/null 2>&1 || true
	amixer -c 0 cset name='RX INT2_1 MIX1 INP0' 'RX1' >/dev/null 2>&1 || true
	amixer -c 0 cset name='COMP1 Switch' on >/dev/null 2>&1 || true
	amixer -c 0 cset name='COMP2 Switch' on >/dev/null 2>&1 || true
	amixer -c 0 cset name='RX INT1 DEM MUX' 'CLSH_DSM_OUT' >/dev/null 2>&1 || true
	amixer -c 0 cset name='RX INT2 DEM MUX' 'CLSH_DSM_OUT' >/dev/null 2>&1 || true
	amixer -c 0 cset name='RX1 Digital Volume' 68 >/dev/null 2>&1 || true
	amixer -c 0 cset name='RX2 Digital Volume' 68 >/dev/null 2>&1 || true
}

find_node() {
	local name=$1 id
	for _ in $(seq 1 20); do
		id=$(pactl list short "${2:-sinks}" 2>/dev/null | awk -v n="$name" '$2 == n {print $1; exit}')
		[ -n "$id" ] && { echo "$id"; return 0; }
		sleep 0.3
	done
	return 1
}

apply_sink() {
	local name=$1 id
	id=$(find_node "$name" sinks) || return 1
	wpctl set-default "$id" 2>/dev/null || true
	wpctl set-mute "$id" 0 2>/dev/null || true
	logger -t raphael-headset "default sink -> $name id=$id" 2>/dev/null || true
}

switch_now() {
	if jack_plugged; then
		enable_headphone_path
		enable_headset_mic
		apply_sink "$HP_NODE"
		sp=$(find_node "$SPK_NODE" sinks || true)
		[ -n "${sp:-}" ] && wpctl set-mute "$sp" 1 2>/dev/null || true
	else
		enable_internal_mic
		sp=$(find_node "$SPK_NODE" sinks || true)
		[ -n "${sp:-}" ] && wpctl set-mute "$sp" 0 2>/dev/null || true
		apply_sink "$SPK_NODE"
	fi
}

for _ in $(seq 1 30); do
	wpctl status >/dev/null 2>&1 && break
	sleep 0.5
done

# At early boot WirePlumber can probe hw:0,0 / hw:0,2 before the ASoC card is
# usable and then never retry, which makes the headphone or the microphone node
# disappear ("capture open failed: EINVAL"). Restart the session manager once
# if one of the expected PCM nodes is missing.
need_restart() {
	pactl list short sinks 2>/dev/null | grep -q "$HP_NODE" || return 0
	pactl list short sources 2>/dev/null | grep -q "capture.2.0" || return 0
	return 1
}

if need_restart; then
	sleep 2
	if need_restart; then
		systemctl --user restart wireplumber 2>/dev/null || true
		sleep 5
	fi
fi

prev=""
while true; do
	cur=$(jack_plugged && echo on || echo off)
	if [ "$cur" != "$prev" ]; then
		sleep 0.25
		switch_now
		prev=$cur
	fi
	sleep 1
done
