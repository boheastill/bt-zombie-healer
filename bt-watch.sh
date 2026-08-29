#!/usr/bin/env bash
# bt-watch v4.1 - watchdog for the MT79xx BT "zombie controller" state.
# Principles:
#   1) Manual recovery wins: an unpaired device entry in pairing mode means the
#      user is fixing it by hand -> watchdog yields for 3 minutes.
#   2) Declare side effects before every rebind (devices about to blink, audio).
#   3) Auto-heal as backstop: keyboard down >25s -> modprobe rebind (proven path).
# Log: ~/.local/state/bt-watch.log
KB_GREP="${BT_WATCH_KB:-X87}"            # device whose loss triggers the heal (keyboard)
LOG_GREP="${BT_WATCH_DEVICES:-X87|MCHOSE}"   # devices tracked for logging / manual-pair detection
LOG="$HOME/.local/state/bt-watch.log"
mkdir -p "$(dirname "$LOG")"
log(){ echo "[$(date '+%F %T')] $*" >> "$LOG"; }
log "bt-watch v4.1 启动(键盘单独判据+手动兼容+副作用声明) (pid $$)"

state=up; down_since=0; notified=0; manual_until=0
sco_last=0; dead_last=0
while true; do
    if bluetoothctl devices Connected 2>/dev/null | grep -qE "$KB_GREP"; then cur=1; else cur=0; fi

    if [ "$cur" = 0 ] && [ "$state" = up ]; then
        state=down; down_since=$SECONDS; notified=0
        log "键盘断开($KB_GREP 离线); 内核现场:"
        journalctl -k --since '-25s' --no-pager 2>/dev/null | grep -i 'hci0' | tail -4 | sed 's/^/    /' >> "$LOG"
    elif [ "$cur" = 1 ] && [ "$state" = down ]; then
        state=up; log "键盘恢复(离线 $((SECONDS - down_since))s)"
    fi

    if [ "$state" = down ] && [ "$notified" = 0 ] && [ $((SECONDS - down_since)) -ge 25 ]; then
        notified=1
        # --- 手动恢复兼容: 未配对的新条目 = 用户在配对模式手动恢复, 自愈让路3分钟 ---
        unpaired=""
        for a in $(bluetoothctl devices 2>/dev/null | grep -iE "$LOG_GREP" | awk '{print $2}'); do
            bluetoothctl info "$a" 2>/dev/null | grep -q 'Paired: yes' || unpaired="$unpaired $a"
        done
        if [ -n "$unpaired" ]; then
            manual_until=$((SECONDS + 180))
            log "手动恢复让路: 未配对条目($unpaired), 3分钟内不自愈"
            notify-send -u normal "蓝牙监控:检测到手动恢复中" \
                "已让路3分钟,你操作完我继续接手。放弃手动就等3分钟,自动修复会接上" 2>/dev/null
        elif [ $SECONDS -lt $manual_until ]; then
            log "(手动恢复窗口内, 跳过自愈)"
        else
            # --- 副作用声明 ---
            will_drop=$(bluetoothctl devices Connected 2>/dev/null | awk '{$1="";print}' | sed 's/^ Device //' | tr '\n' ',')
            audio_on=$(pactl list sinks short 2>/dev/null | grep bluez | grep -c RUNNING || true)
            log "自动重绑 | 副作用: 在线设备闪断2-5秒[${will_drop:-无}] 蓝牙音频流[$audio_on]"
            if sudo -n /usr/local/bin/bt-rebind.sh >/dev/null 2>&1; then
                log "重绑完成, 等待敲键回连"
                extra=""; [ "${audio_on:-0}" -gt 0 ] 2>/dev/null && extra=",音频中断过"
                notify-send -u normal "蓝牙监控:已自动修复" \
                    "驱动已重绑,敲任意键即回。副作用:在线蓝牙设备刚才闪断了几秒$extra" 2>/dev/null
            else
                log "自动重绑失败(无免密权限?)"
                notify-send -u critical "蓝牙监控:键鼠失联" "自动重绑失败。修复: bash ~/bt-fix.sh" 2>/dev/null
            fi
        fi
    fi

    # 先兆特征(限频10分钟)
    if journalctl -k --since '-15s' --no-pager 2>/dev/null | grep -q 'SCO packet for unknown connection handle'; then
        [ $((SECONDS - sco_last)) -ge 600 ] && { sco_last=$SECONDS; log "先兆: SCO unknown handle(适配器带伤)"; }
    fi
    if journalctl -k -u bluetooth --since '-15s' --no-pager 2>/dev/null | grep -qE 'Wrong size of start discovery|hci0.*timed out'; then
        [ $((SECONDS - dead_last)) -ge 600 ] && { dead_last=$SECONDS; log "红警: 栈半死特征(NotReady/Wrong size)"; }
    fi

    sleep 10
done
