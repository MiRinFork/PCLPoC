# PCL 2.99.0.1 复查（2026-10-25）

> 写：DeepSeek Harness aka deepseek-flash

## 结论

没删。

2.99.0.1 跟远程执行有关的改动只有一个：给 `notice.json` 的 `setup` 加了个 12 个键的
黑名单，把 `LaunchAdvanceRun` 这些直接堵了。`slientupdate` 那条静默更新链还是老样子，
0 click：

- `HasUpdatePermission => true`（`ModSecret.cs:402`）
- `slientupdate` 直接 `UpdateStart(true)`（1513–1530）
- 下载地址来自未签名的 `ServerConfig`（1017–1037）
- 没有哈希，没有签名，zip 解压覆盖 `PCL\Plain Craft Launcher 2.exe`（198–211）
- 静默时只置 `IsUpdateWaitingRestart`，退出时 `UpdateRestart(false)` 启动新 exe
  （`FormMain.cs:1968`、`ModSecret.cs:1084`）

按报告原来的前提——能控制公告 CDN 的内容，或者做 DNS/TLS 中间人——还是能零点击换掉
启动器本体。

| | 2.99.0.0 | 2.99.0.1 |
|---|---|---|
| 启动拉 `notice.cfg` / `notice.json` / `ServerConfig.json` | 有 | 有 |
| 配置内容签名 / 更新包哈希 | 无 | 无 |
| `setup` 写设置 | 任意键 | 12 键黑名单 |
| `setup.LaunchAdvanceRun` → `cmd /c` | 可写 | 被拦 |
| `slientupdate` → 任意 zip → 替换自身 | 有 | 有 |
| `HasUpdatePermission` | `=> true` | `=> true` |

## 动态验证（2026-10-25）

已在隔离的 Windows 10 Enterprise LTSC 2021 VM 上复跑：

- 方法一：PCL 日志 `被禁止的设置项：LaunchAdvanceRun`，无 marker；
- 方法二：staging exe 与 `update.zip` entry 的 SHA-256 相同，marker 写入，Calculator 拉起；
- 视频与证据：[`vm-test/`](vm-test/README.md)、[`pcl-2.99.0.1-poc-demo.mp4`](vm-test/pcl-2.99.0.1-poc-demo.mp4)；
- 复现脚本：[`repeat/`](../../repeat/README.md)。

## 样本

用户给的 `PCL 正式版 2.99.0.1.zip`，SHA-256
`4d239a62ed66fb9ebcf4633fd881eb098e9a7e4f296f0e414b58aa2f1f7f7830`。里面一个
`Plain Craft Launcher 2.exe`，6,013,952 字节，SHA-256
`0db34e19d9eeb6d496d20fabe786ec16bbd36ba6b0ccdc8d29cb7e909c114397`。PE 的
`Security Directory` 还是 0，没签名。

官方仓库 `Hex-Dragon/PCL2` 的发布提交是 `93ede5d`（`2.99.0.1 正式版`）。这个提交里的
`最新正式版.zip` 和用户给的 zip 逐字节一样，解出来的 exe 也一样。不是二次打包。

## 反编译

`ilspycmd` 反编译。

diff：

```text
.cs     变了 19 / 164
.baml   变了 51
其它    2 个（PCL.Resources.resx、Plain Craft Launcher 2.csproj）
```

19 个 `.cs` 里大部分是版本号 413 → 415、更新日志、删 MC 下载入口和 UI。

跟远程执行有关
的只有 `ModSecret.cs` 的 `setup` 黑名单。

这次在 Windows 10 LTSC 2021 上重跑了 PoC。1-Click RCE 被拦截，0-Click RCE 复现成功。

详见 [vm-test](vm-test/README.md)。

## 1-Click RCE 缺陷死啦！

```csharp
// PCL/ModSecret.cs:1495-1510
case "setup":
{
    JObject val5 = (JObject)val4.Value;
    string[] source = new string[12]
    {
        "LaunchAdvanceRun", "LaunchAdvanceJvm", "LaunchAdvanceGame", "UiCustomNet",
        "HintCustomCommand", "LaunchArgumentJavaAll", "LaunchArgumentJavaSelect",
        "SystemSystemCache", "LaunchFolderSelect", "LaunchFolders",
        "ToolDownloadCert", "CacheAuthServerServer"
    };
    foreach (KeyValuePair<string, JToken> item4 in val5)
    {
        if (source.Contains(item4.Key))
        {
            throw new Exception("被禁止的设置项：" + item4.Key); // 遇到黑名单的 key 直接退出抛出异常。
        }
        Settings.Set(item4.Key, item4.Value.ToString());
    }
    break;
}
```

异常被每个 action 外面的 `catch` 捕获，日志里只留一句“执行 PCL 服务器公告动作失败”。

`setup` 功能依旧保留。

1-Click RCE 缺陷已近无利用价值。
## <img src="update.png" align="right" alt="老实更新，很枯燥吧？"  width="30%" > 0-Click RCE 缺陷：老实更新，很枯燥吧？ 

依旧是。

1. 启动下载 `notice.cfg`：

   ```csharp
   // PCL/ModSecret.cs:1324-1325
   text3 = ModNet.NetRequestByClientRetry(
       "https://pcl2-server-1253424809.file.myqcloud.com/notice.cfg{CDN}");
   num3 = (int)Math.Round(ModBase.Val(StringExtensions.Split(text3, "|", false)[0]));
   ```

2. 下载 `ServerConfig.json`：

   ```csharp
   // PCL/ModSecret.cs:1378-1383
   double num4 = ModBase.Val(StringExtensions.Split(text3, "|", false)[4]);
   if ((double)num < num4)
   {
       ModNet.NetDownloadByClient(
           "https://pcl2-server-1253424809.file.myqcloud.com/ServerConfig.json{CDN}", text);
       ServerConfig = (JObject)FileUtils.ReadAsJson(text, (Encoding)null, (Type)null);
   }
   ```

3. 做 `action`：

   ```csharp
   // PCL/ModSecret.cs:1403-1404
   text4 = ModNet.NetRequestByClientRetry(
       "https://pcl2-server-1253424809.file.myqcloud.com/notice.json{CDN}",
       null, null, null, null, "*/*", null, RequireJson: true);
   FileUtils.Write(ModBase.PathTemp + "Cache\\Notice.json", text4, (Encoding)null);
   ```

4. `slientupdate`  `true`：

   ```csharp
   // PCL/ModSecret.cs:402
   private static bool HasUpdatePermission => true; // 永远

   // PCL/ModSecret.cs:1513-1530
   case "update":
   case "slientupdate":
   {
       _ = (JObject)val4.Value;
       bool flag3 = Operators.CompareString(val4.Name, "slientupdate", false) == 0;
       if (!HasUpdatePermission)
       {
           if (!flag3) { InputPotatoCode(IsUpdating: true); }
           if (!HasUpdatePermission) { break; }
       }
       UpdateStart(flag3);
       break;
   }
   ```

5. `UpdateStart` 依旧自定义不固定 URL：

   ```csharp
   // PCL/ModSecret.cs:1017-1037
   JObject val = (JObject)ServerConfig["Update"][(object)ModBase.BuildTypes.Release.ToString()];
   if (val.ContainsKey("PatchUrls") && StringExtensions.StartsWithF(UpdateMark, "Empty", false))
       _0024VB_0024Local_Urls = val["PatchUrls"].ToObject<List<string>>();
   else if (val.ContainsKey("DownloadUrls"))
       _0024VB_0024Local_Urls = val["DownloadUrls"].ToObject<List<string>>();

   _0024VB_0024Local_Extension = "." + PathUtils.GetExtension(
       StringExtensions.BeforeLast(_0024VB_0024Local_Urls.First(), "{CDN}", false));
   _0024VB_0024Local_LocalPath = string.Format("{0}{1}.{2}{3}",
       ModMain.RequestTaskTempFolder(), "2.99.0.1", 50, _0024VB_0024Local_Extension);

   Task.Output = new ModNet.NetFile[1]
   {
       new ModNet.NetFile(_0024VB_0024Local_Urls, _0024VB_0024Local_LocalPath)
   }.ToList();
   ```

    同类型启动器至少校验 SHA256。

6. 依旧覆盖。

   ```csharp
   // PCL/ModSecret.cs:198-211
   if (Operators.CompareString(_0024VB_0024Local_Extension, ".zip", false) == 0)
   {
       FileUtils.ExtractToDirectory(_0024VB_0024Local_LocalPath, Paths.Base + "PCL\\",
           default(CancellationToken), (ProgressProvider)null);
   }
   else
   {
       MsDelta.Apply(ModBase.PathExe, _0024VB_0024Local_LocalPath,
           $"{Paths.Base}PCL\\Plain Craft Launcher 2.exe");
   }
   if (_0024STATIC_0024UpdateStart_00240212151280E91E_0024IsSilentUpdate)
   {
       IsUpdateWaitingRestart = true;
       return;
   }
   ```

7. 依旧静默更新。

   ```csharp
   // PCL/FormMain.cs:1968
   if (ModSecret.IsUpdateWaitingRestart)
   {
       ModSecret.UpdateRestart(TriggerRestartAndByEnd: false);
   }

   // PCL/ModSecret.cs:1084-1097
   public static void UpdateRestart(bool TriggerRestartAndByEnd)
   {
       try
       {
           IsUpdateWaitingRestart = false;
           string fileName = Paths.Base + "PCL\\Plain Craft Launcher 2.exe";
           string text = $"--update {Process.GetCurrentProcess().Id} \"{AppDomain.CurrentDomain.SetupInformation.ApplicationName}\" \"{AppDomain.CurrentDomain.SetupInformation.ApplicationName}\" {TriggerRestartAndByEnd}";
           ModBase.StartProcess(new ProcessStartInfo(fileName)
           {
               WindowStyle = ProcessWindowStyle.Hidden,
               CreateNoWindow = true,
               Arguments = text
           });
           if (TriggerRestartAndByEnd)
           {
               ModMain.FrmMain.EndProgram(SendWarning: false);
           }
       }
       catch (Win32Exception ex)
       {
           // 被拦截时提示用户手动替换
       }
   }
   ```

## 复现

```bash
git clone https://github.com/Hex-Dragon/PCL2.git upstream
cd upstream

# 2.99.0.0
git checkout 6b9a50d
unzip -q 最新正式版.zip -d ../2990
ilspycmd -p -o ../decompiled-2990 ../2990/"Plain Craft Launcher 2.exe"

# 2.99.0.1
git checkout 93ede5d
unzip -q 最新正式版.zip -d ../2991
ilspycmd -p -o ../decompiled-2991 ../2991/"Plain Craft Launcher 2.exe"

cd ..
diff -rq decompiled-2990 decompiled-2991 | grep '\.cs '
diff -u decompiled-2990/PCL/ModSecret.cs decompiled-2991/PCL/ModSecret.cs
```

## 文件

```text
analysis/2.99.0.1/
├── README.md                       本文件
├── diff/
│   ├── ModSecret.diff              ModSecret.cs 的完整 unified diff
│   ├── other-modules.diff          其余 18 个 .cs 的 diff
│   ├── changed-files.txt           72 个差异文件清单
│   └── summary.txt                 差异计数
└── evidence/
    ├── hashes.txt                  zip / exe / 官方包哈希
    ├── provenance.md               来源与比对过程
    └── snippets.md                 2.99.0.1 关键代码片段
```
