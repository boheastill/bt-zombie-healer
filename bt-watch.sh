#!/usr/bin/env bash
# bt-watch — 键鼠蓝牙失联监控 v2(sliver,2026-08-29 会诊后升级)
# 职责:
#   1) 每 30s 轮询键鼠连接;断开/恢复打点(含离线时长);断开瞬间抓内核 hci0 现场
#   2) 监听先兆日志特征(agy/kimi 会诊特征表):
#      - "SCO packet for unknown connection handle" → 黄警(适配器即将/已经带伤)
#      - "Wrong size of start discovery" / "hci0.*timed out" → 红警(栈半死)
#   3) 键盘失联>90s 弹一次桌面通知(指向 bt-fix.sh)
# 日志: ~/.local/state/bt-watch.log ; 病因: ~/bh-workspace/docs/sliver-bt-stability/
set -u
DEVICE_GREP="${BT_WATCH_DEVICES:-X87|MCHOSE}"   # edit to your device name fragments
LOG="$HOME/.local/state/bt-watch.log"
mkdir -p "$(dirname "$LOG")"
log(){ echo "[$(date '+%F %T')] $*" >> "$LOG"; }
log "bt-watch v3 启动(失联自动重绑) (pid $$)"

kbd=up mouse=up; kbd_down=0 mouse_down=0; kbd_notified=0
sco_last=0; dead_last=0
while true; do
    conn=$(bluetoothctl devices Connected 2>/dev/null)
    echo "$conn" | grep -qE "$DEVICE_GREP" && k=1 || k=0
    echo "$conn" | grep -qE "$DEVICE_GREP" && m=1 || m=0

    # 键盘状态机
    if [ "$k" = 0 ] && [ "$kbd" = up ]; then
        kbd=down; kbd_down=$SECONDS; kbd_notified=0
        log "键盘断开; 内核现场:"
        journalctl -k --since '-45s' --no-pager 2>/dev/null | grep -i 'hci0' | tail -4 | sed 's/^/    /' >> "$LOG"
    elif [ "$k" = 1 ] && [ "$kbd" = down ]; then
        kbd=up; log "键盘恢复(离线 $((SECONDS - kbd_down))s)"
    elif [ "$kbd" = down ] && [ "$kbd_notified" = 0 ] && [ $((SECONDS - kbd_down)) -ge 25 ]; then
        kbd_notified=1
        log "键盘失联>25s, 自动重绑蓝牙驱动..."
        if sudo -n /usr/local/bin/bt-rebind.sh >/dev/null 2>&1; then
            log "重绑完成, 等待敲键回连"
            notify-send -u normal "蓝牙监控:已自动修复" \
                "检测到键盘失联,驱动已重绑。\n敲任意键即回连(若仍无反应: 断电重启键盘)" 2>/dev/null
        else
            log "自动重绑失败(无免密权限?)"
            notify-send -u critical "蓝牙监控:键盘失联" \
                "超 60 秒未恢复且自动重绑失败。\n修复: bash ~/bt-fix.sh" 2>/dev/null
        fi
    fi

    # 鼠标状态机(只打点不通知,鼠标多数能自愈)
    if [ "$m" = 0 ] && [ "$mouse" = up ]; then
        mouse=down; mouse_down=$SECONDS; log "鼠标断开"
    elif [ "$m" = 1 ] && [ "$mouse" = down ]; then
        mouse=up; log "鼠标恢复(离线 $((SECONDS - mouse_down))s)"
    fi

    # 先兆特征监控(限频:同类 10 分钟内只报一次)
    if journalctl -k --since '-35s' --no-pager 2>/dev/null | grep -q 'SCO packet for unknown connection handle'; then
        if [ $((SECONDS - sco_last)) -ge 600 ]; then
            sco_last=$SECONDS
            log "先兆: SCO unknown handle 出现(适配器带伤, 键鼠可能即将失联)"
            notify-send -u normal "蓝牙监控:SCO 异常" "适配器状态受损先兆,键鼠断开后可能无法自动恢复。发作时: bash ~/bt-fix.sh" 2>/dev/null
        fi
    fi
    if journalctl -k -u bluetooth --since '-35s' --no-pager 2>/dev/null | grep -qE 'Wrong size of start discovery|hci0.*timed out'; then
        if [ $((SECONDS - dead_last)) -ge 600 ]; then
            dead_last=$SECONDS
            log "红警: 蓝牙栈半死特征(NotReady/Wrong size), 已通知"
            notify-send -u critical "蓝牙监控:栈半死" "检测到适配器半死特征。恢复: bash ~/bt-fix.sh 或等软复位" 2>/dev/null
        fi
    fi

    sleep 10
done
