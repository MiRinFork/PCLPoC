# PCL 2.99.0.1 公告执行 PoC：Windows VM 自动演示复现包

> 仅用于授权的隔离 Windows 虚拟机。不要对真实用户机、生产环境或未授权设备运行。

## 结果先说

- **方法一** `notice.json -> actions.setup -> LaunchAdvanceRun`：
  2.99.0.1 的 12 键黑名单会拦截 `LaunchAdvanceRun`，payload **不会执行**。
- **方法二** `notice.cfg + slientupdate -> ServerConfig -> update.zip -> PCL\Plain Craft Launcher 2.exe`：
  **仍然可用**，零点击；PCL 正常退出时执行下载的 exe。
- 本目录的演示按 7 步录制：复制新版 zip、解压、跑 PoC、方法一被拦、删掉 PCL、方法二成功。

演示视频里方法一显示的是“被拦截”，不是计算器弹出。这是 2.99.0.1 的真实行为，
也是这次复查的结论：**黑名单只堵了方法一，没有堵方法二**。

## 已有产出（2026-10-25）

- 最终视频：`analysis/2.99.0.1/vm-test/pcl-2.99.0.1-poc-demo.mp4`
  （2:03，1920×1080，烧录中文字幕）。
- 证据：`analysis/2.99.0.1/vm-test/evidence/`。
- **逐帧原始素材**：`vm/frames/final3/`，1434 张 1920×1080 JPEG（8 fps）+
  `index.csv`，约 270 MB；已保留，不删除。另有 `vm/frames/final`、
  `final2` 两个布局调试 take。
- 最终视频只取 step1→end+12s（帧 101–1087）；`make-video.sh` 不会删除源帧。

## 目录

```text
repeat/
├── build-toolkit.sh        # 生成带 MBR + FAT32 分区的 USB 工具盘 toolkit.img
├── init-vm.sh              # 建 60G qcow2，复制 toolkit.img 到 VM_DIR
├── run-vm.sh               # 启动 QEMU（install / demo 两个阶段）
├── record.sh               # QMP 帧抓取录屏（自动按空格过 ISO 启动提示）
├── record.py / qmp.py      # 录制与 QMP 客户端
├── extract-evidence.sh     # 关机后从 FAT 镜像取出 evidence
├── make-video.sh           # 按时间线裁剪 + 烧中文字幕 + 编码
├── make_srt.py             # 从 demo-timeline.csv 生成 SRT
├── subtitles/captions.tsv  # 事件 ID → 中文字幕
├── toolkit/
│   ├── autounattend.xml    # Windows 10 LTSC 2021 无人值守
│   └── pcl-test/
│       ├── firstlogon.cmd  # FirstLogonCommands 入口
│       ├── prepare.ps1     # 建 lab 环境、复制 PoC、注册重试任务
│       ├── demo.ps1        # 7 步演示的“导演”脚本
│       ├── lib-gui.ps1     # 分辨率、控制台字体、窗口排布
│       ├── arrange-windows.ps1
│       ├── close-pcl.ps1
│       ├── watch-staging.ps1
│       └── PCLPoC/         # PoC 脚本，不含 certs/ 私钥
└── README.md
```

## 前置条件

- Linux + KVM + QEMU（本机验证版本 11.1.2），Python 3，bash。
- `sfdisk`、`mkfs.vfat`（dosfstools）、`mtools`、`ffmpeg`（带 libass）、
  `Noto Sans CJK SC` 字体。
- Windows 10 Enterprise LTSC 2021 x64 en-US ISO：
  `en-us_windows_10_enterprise_ltsc_2021_x64_dvd_d289cf96.iso`。
- PCL 2.99.0.1 发布包：
  `PCL 正式版 2.99.0.1.zip`，SHA-256
  `4d239a62ed66fb9ebcf4633fd881eb098e9a7e4f296f0e414b58aa2f1f7f7830`。
- 约 60G 稀疏磁盘空间、4G 内存、4 vCPU。

ISO 和 PCL zip **不随本目录分发**，请从合法来源自备。

## 快速开始

```bash
cd repeat

# 1. 生成工具盘（默认在仓库根目录找 PCL*.zip，也可 PCL_ZIP=... 指定）
./build-toolkit.sh

# 2. 建 VM 磁盘；默认 $HOME/.HHD/PCLPoC-VM
./init-vm.sh

# 3. 先开录屏（后台），再启动安装
./record.sh frames/install &
./run-vm.sh install
wait
```

安装是无人值守的：约 10–25 分钟后进入首次登录，`firstlogon.cmd -> prepare.ps1 -> demo.ps1`
自动开始 7 步演示，最后关机。`record.sh` 会一直录到 QEMU 退出。

```bash
# 4. 取证据
./extract-evidence.sh

# 5. 裁出演示段、烧字幕
./make-video.sh frames/install pcl-2.99.0.1-poc-demo.mp4
```

如果第一次演示失败，VM 会关机。往工具盘放一个重试标记，再以 demo 阶段重启：

```bash
echo retry > /tmp/retry.flag
mcopy -i "$HOME/.HHD/PCLPoC-VM/toolkit.img@@1M" /tmp/retry.flag ::/pcl-test/retry.flag
./record.sh frames/demo &
./run-vm.sh demo
wait
```

`prepare.ps1` 注册了登录任务 `PCLPoCRetry`；它检查 `pcl-test\retry.flag`，存在就重跑
`firstlogon.cmd`。AutoLogon 次数为 999，所以 `run-vm.sh demo` 会自动登录并开始。

## 7 步演示对应关系

| 视频字幕事件 | 画面 |
|---|---|
| `step1` | 进入 Windows 桌面，终端左、桌面右，显示 OS/用户/分辨率 |
| `step2` | 终端复制 `PCL 2.99.0.1.zip` 到桌面，右侧资源管理器刷新 |
| `step3` | 解压 `Desktop\PCL`，显示 exe 大小与 SHA-256 |
| `step4` | 启动本地 HTTPS 公告服务器 + hosts + 自签 CA；PCL 在右侧打开 |
| `method1` | `notice.json` 里的 `setup.LaunchAdvanceRun` |
| `blocked` | PCL 日志出现 `被禁止的设置项：LaunchAdvanceRun`，无 marker |
| `step6` | 删除整个 `Desktop\PCL` |
| `step7` | 重新解压，`slientupdate` 下载 `update.zip` 覆盖 `PCL\Plain Craft Launcher 2.exe` |
| `success` | PCL 退出后 marker 出现；staging exe 与 zip entry 哈希一致 |
| `end` | 右侧 Notepad 展示 `RESULT.txt`，终端总结 |

## 关键实现点

### 1. USB 必须是“可移动介质”

QEMU `usb-storage` 的 `removable` 默认是 `off`。这样 Windows 会把工具盘当成固定磁盘，
Windows Setup **不会**扫描它上面的 `autounattend.xml`，而是停在语言选择页。

`run-vm.sh` 里固定使用：

```text
-device usb-storage,drive=usb0,bus=xhci.0,removable=on,serial=PCLTOOL
```

工具盘是 MBR + 单个 FAT32 分区（type 0x0c），`autounattend.xml` 在分区根目录。
Windows PE 把它挂成可移动盘后，Setup 会自动读取。

### 2. 首次登录自动跑

`autounattend.xml` 的 `FirstLogonCommands` 在 C:–K: 里找 `pcl-test\firstlogon.cmd`，
启动 `prepare.ps1`（最小化）→ `demo.ps1`（正常窗口）。`prepare.ps1` 负责：

- `HKCU\Software\PCL\SystemEulaVersion=2`，跳过 PCL 用户协议；
- 复制 PoC 到 `C:\PCLPoC`；
- 加 Defender 排除、关通知/休眠；
- 注册重试任务；
- 启动演示。

首次启动 `SystemLastVersionReg=0` 时 PCL 不会弹更新日志（源码条件
`LastVersionCode > 0 && num < 413`），所以不需要预跑 PCL。


### 3. 终端和 PCL 各占半屏（150% DPI 注意）

Windows 10 LTSC 2021 默认可能是 150% 缩放。demo 会声明 DPI 感知，但控制台字体仍按
150% 放大；因此：

- 控制台固定 66 列（`Set-ConsoleSize -Columns 66 -Rows 36`），实际约 1190 px；
- PCL 通过 `HKCU\...\AppCompatFlags\Layers` 的 `~ HIGHDPIAWARE` 标记按 100% 渲染，
  实际约 670 px，位于 x≈1250–1920；
- 两者留有空隙、互不遮挡；`demo.log` 里的 `console=918 pcl=998` 是计算值，
  实际像素以录屏为准。

字幕在 `make-video.sh` 里用 `FontSize=9`：libass 对无 PlayRes 的 SRT 会按 1080p
放大，9 约等于 34 px；不要按字面理解成 9 px。

`demo.ps1` 用 `ChangeDisplaySettings` 尝试 1920×1080（回退 1600×900/1366×768），
把控制台放在左侧；`arrange-windows.ps1` 每 500ms 把 PCL/calc 移到右侧。
这样终端不会被 PCL 挡住，PCL 也不会被终端挡住。

### 4. 录制与字幕

- `record.py` 通过 QMP `screendump` 以约 8fps 抓帧，写 `frames/frame-%06d.jpg`
  和 `index.csv`（帧号、epoch 毫秒）。
- `demo.ps1` 写 `evidence/demo-timeline.csv`（事件 ID、epoch 毫秒）。
- `make_srt.py` 找 `step1` 最近的帧作为视频起点，按事件 epoch 生成 `demo.srt`；
  `make-video.sh` 从该帧开始编码并烧字幕。
- 安装阶段的帧不会被编码；视频从 1920×1080 的桌面开始，尺寸一致。

QMP 是单客户端协议。需要手动发键/截图时，先停掉 `record.sh`，否则第二个客户端
连不上。

## 预期结果

方法一（`-Mode launch`）：

- 服务器收到 `/notice.cfg`、`/notice.json`；
- PCL 日志出现 `执行 PCL 服务器公告动作失败（setup, ...）`，异常消息含
  `被禁止的设置项：LaunchAdvanceRun`；
- `%TEMP%\pcl-poc-marker.txt` **不存在**。

方法二（`-Mode update`）：

- 服务器收到 `/notice.cfg`、`/ServerConfig.json`、`/notice.json`、`/update.zip`；
- `Desktop\PCL\PCL\Plain Craft Launcher 2.exe` 出现（payload，约 4–5 KB）；
- 关闭 PCL 后 marker 出现，内容形如
  `2026-... pid=... args=--update ...`；
- `staging.exe` 与 `update.zip` 内 `Plain Craft Launcher 2.exe` 的 SHA-256 一致；
- `poc-run.log` 末尾有 `[+] SUCCESS: payload executed.`。

`RESULT.txt`、`demo.log`、`poc-run.log`、`server.out.log`、PCL `Log*.txt` 都在
`evidence/` 里。

## 隐私与安全

- 本目录**不包含** ISO、PCL zip、CA 私钥或主机用户名。
- PoC 默认走纯 PowerShell 服务端，CA 在 VM 内用 `New-SelfSignedCertificate` 现生成，
  退出时从证书库删除；`certs/` 不复制进工具盘。
- 仓库根目录的 `certs/*.key`、`server.pfx` 属于实验室私钥材料；不要发布。
  `repeat/.gitignore` 已忽略 `*.key`、`*.pfx` 和 `PCLPoC/certs/`。
- VM 账户是通用的 `lab`，密码 `PclPoC!2026` 仅用于隔离实验；请按自己的环境修改
  `autounattend.xml` 后重建工具盘。
- VM 无网卡，PoC 只访问 `127.0.0.1`；不要把该 VM 接入真实网络。
- VM 磁盘运行期间会持有本次实验 CA 的私钥；`$VM_DIR` 应保持私有，不要分发。
- `evidence/` 和录屏可能包含 lab VM 的路径/用户名/PID；公开前自行检查。

## 已知限制

- 方法一在 2.99.0.1 上**必然被拦**，本演示如实展示拦截。若要看 `LaunchAdvanceRun`
  真正执行，需要 2.99.0.0 + 一个可启动的 Minecraft 实例，不在本复现包范围内。
- 1920×1080 依赖 QEMU stdvga + Windows 基本显示驱动；若回退到 1024×768，
  左右分屏会很挤，可改用 virtio-gpu/QXL 驱动后重跑。
- Windows 10 LTSC 可能没有 `calc.exe`；marker 和 staging hash 才是执行证据。
- 安装耗时取决于磁盘/CPU；`.HHD` 在加密卷上会更慢。
