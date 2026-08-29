# bt-zombie-healer(中文版)

**一种静默的 MediaTek MT79xx 蓝牙故障:定性它,并让它对你隐形。**

*定性(知识)是本项目;自愈脚本只是顺手的事。*

你的蓝牙键鼠一直好好的,某天起:用着用着断开(可能伴随某个字符狂按不止),然后再也连不回——重配"能修",重启"能修",而蓝牙面板始终显示一切健康。不是外设的错,也(大概率)不是 BlueZ 的错。

> **赶时间**: `sudo modprobe -r btusb btmtk && modprobe btusb`,然后敲一下设备任意键。每次都立刻好?你大概率就是本文说的故障。看门狗会自动替你做这件事。

## 一、同一个器官,好几种病——我们负责其中一种

散落在各发行版追踪器里的这些抱怨看似无关,各有土方。**有效的土方就是鉴别诊断**:

| 人们报告什么 | "有效"的土方 | 判定 | 出处 |
|---|---|---|---|
| "挂起/更新后蓝牙适配器消失" | 彻底断电 / 重载 btusb | 适配器消失病 | [bazzite#3112](https://github.com/ublue-os/bazzite/issues/3112) 等 |
| "MT7925 初始化失败 WMT 超时" | 等 7.1-rc 上游修复 | 初始化失败病 | [pop-os#4001](https://github.com/pop-os/pop/issues/4001) |
| "固件更新后蓝牙死了" | `usbcore.autosuspend=-1` | autosuspend 处理不当 | [RH#2372880](https://bugzilla.redhat.com/show_bug.cgi?id=2372880) |
| "BLE 设备断开就连不上,重启才行" | `modprobe -r btusb` | **僵尸态(本项目)** | [AskUbuntu](https://askubuntu.com/questions/1387234/bluetooth-only-works-after-reloading-module-btusb) 等 |

## 二、模型:僵尸态

人话:蓝牙芯片没有死透,它只是**半聋**——你直接问它话它都答,但设备来敲门它永远听不见。

三个主张,按确定性递减:

1. **(直接观测)** HCI 命令面活着、BLE 接受路径死了:面板健康、扫描能开,但目标设备**零广告回调**、connect 全部超时。铁证(使用中两次抓到):`kernel: hci0: ACL packet for unknown connection handle`——键盘的击键数据到达,主机侧连接表里却没有这个 handle(活连接被记账方丢弃,host 还是 controller 侧暂不可分)。用户观感:卡键→静默。
2. **(直接观测)** 病是**状态性、渐进的**:正常 LE 睡眠/重连循环跑数日后出现(三个启动周期断连率大致稳定:8/25h、10/39h、6/10h),有内核前兆(`Wrong size of start discovery`、SCO 句柄泄漏),驱动重绑即愈(同 MAC、无需重配)。
3. **(强推断,可证伪)** 故障期间外设一直在广播、是控制器停止了解析/接受。旁证:同一批抓包里,配对模式(静态地址)广播能收到(-58dBm)而 RPA 定向重连永远收不到——**广播面活着,解析面死了**。未经第二接收器直证:你遇到此故障时,手机装 nRF Connect 扫一分钟,两个方向都能把它变成直接证据。

## 三、什么能修、什么不能

| 动作 | 效果 |
|---|---|
| `modprobe -r btusb btmtk && modprobe btusb` | **可靠即时恢复**(同 [Framework 官方 KB](https://knowledgebase.frame.work/ubuntu-bluetooth-S1PGxfho) 流程) |
| `systemctl restart bluetooth` | 时灵时不灵 |
| USB `authorized 0/1` | 理论更优雅;**本机实测一次搞坏 bluez 设备表**——别用 |
| 删除重配 | 能修但破坏性大:两台三模外设实测**每次重配 MAC+1**(…6B→6C→6D→6E),毁掉配对和证据。**先重绑,永远别删** |
| udev 禁 USB autosuspend | 治"重连慢"那个亚型;好习惯,非根治 |
| WirePlumber 禁 HFP/HSP | 除掉最大 SCO 诱因;代价=蓝牙耳机无麦 |

## 四、看门狗(顺手的事)

用户级 systemd 服务,**检测**=10 秒轮询连接状态,**恢复**=键盘离线>25 秒→sudoers 白名单重绑→最坏 35 秒转绿。设计三原则:手动恢复永远优先(检测到配对模式广播就让路 3 分钟)/每次重绑先声明副作用/`BT_WATCH_FORENSICS=1` 取证模式只告警不自动修。日志即取证档案。

```bash
./install.sh     # 有守卫: 检测不到 MediaTek 蓝牙(13d3/0e8d/0489)直接中止
./uninstall.sh   # 完整反向卸载
```

## 五、开放问题与如何参与

尚未做的廉价实验(每个都能收紧模型):①故障时第二接收器抓包(手机 nRF Connect 或第二只 USB 蓝牙跑 btmon);②故障时 `btmgmt conn-info` 看 controller 侧连接表——到底是谁的记账丢了 handle;③固件二分(20260724↔20260224)进行中。遇到故障请按 [issue 模板](.github/ISSUE_TEMPLATE/bug_report.md) 报告——证实或证伪都有价值。

## 六、根因状态(诚实)

头号嫌疑 MediaTek 固件(闭源微码),次嫌 btusb URB 生命周期。**截至内核 7.1,据我们所知(检索过 linux-bluetooth 列表与主线 btusb/btmtk 提交)没有针对此静默路径的直接修复**。我们接受的改判证据:重绑后 btmon 若显示固件侧残留状态→固件;URB 错误若稳定先于症状→btusb。凭证据改判,不凭感觉。

## 七、范围

**验证时点 2026-08-29**:MT7922(USB 13d3:3585)、Fedora 44、内核 7.1.10、BlueZ 5.79 与 5.87。相关报告提示 MT7921/7925 同族(未验证)。这是**缓解不是根治**,目标是让你感觉不到病。MIT。[English README](README.md)
