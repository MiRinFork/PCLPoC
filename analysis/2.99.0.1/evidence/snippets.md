# 2.99.0.1 关键代码片段

反编译：`ilspycmd 9.1 -p -o decompiled "Plain Craft Launcher 2.exe"`
行号对应 2.99.0.1 反编译结果。

## 1. 启动时拉取配置

```csharp
// PCL/ModSecret.cs:382
public static ModLoader.LoaderTask<int, int> ServerLoader =
    new ModLoader.LoaderTask<int, int>("PCL 配置更新", ServerSub, null, ThreadPriority.BelowNormal);

// PCL/ModSecret.cs:1324-1325
text3 = ModNet.NetRequestByClientRetry(
    "https://pcl2-server-1253424809.file.myqcloud.com/notice.cfg{CDN}");
num3 = (int)Math.Round(ModBase.Val(StringExtensions.Split(text3, "|", false)[0]));
```

## 2. 按 notice.cfg 的版本号刷新 ServerConfig

```csharp
// PCL/ModSecret.cs:1378-1383
double num4 = ModBase.Val(StringExtensions.Split(text3, "|", false)[4]);
if ((double)num < num4)
{
    Logger.Info($"本地配置版本号：{num}，服务器配置版本号：{num4}，需要更新", ...);
    ModNet.NetDownloadByClient(
        "https://pcl2-server-1253424809.file.myqcloud.com/ServerConfig.json{CDN}", text);
    ServerConfig = (JObject)FileUtils.ReadAsJson(text, (Encoding)null, (Type)null);
}
```

## 3. 拉取并缓存 notice.json

```csharp
// PCL/ModSecret.cs:1403-1404
text4 = ModNet.NetRequestByClientRetry(
    "https://pcl2-server-1253424809.file.myqcloud.com/notice.json{CDN}",
    null, null, null, null, "*/*", null, RequireJson: true);
FileUtils.Write(ModBase.PathTemp + "Cache\\Notice.json", text4, (Encoding)null);
```

## 4. setup 黑名单

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
            throw new Exception("被禁止的设置项：" + item4.Key);
        }
        Settings.Set(item4.Key, item4.Value.ToString());
    }
    break;
}
```

`Settings.Entries` 的构造是 `... .ToDictionary(e => e.Key)`，即默认
`Dictionary<string, Setting>` comparer，键名大小写敏感。

## 5. 静默更新入口与恒真权限

```csharp
// PCL/ModSecret.cs:402
private static bool HasUpdatePermission => true;

// PCL/ModSecret.cs:1513-1530
case "update":
case "slientupdate":
{
    _ = (JObject)val4.Value;
    bool flag3 = Operators.CompareString(val4.Name, "slientupdate", false) == 0;
    if (!HasUpdatePermission)
    {
        if (!flag3)
        {
            InputPotatoCode(IsUpdating: true);
        }
        if (!HasUpdatePermission)
        {
            break;
        }
    }
    UpdateStart(flag3);
    break;
}
```

## 6. 更新 URL 与下载

```csharp
// PCL/ModSecret.cs:1017-1037
JObject val = (JObject)ServerConfig["Update"][(object)ModBase.BuildTypes.Release.ToString()];
if (val.ContainsKey("PatchUrls") && StringExtensions.StartsWithF(UpdateMark, "Empty", false))
{
    _0024VB_0024Local_Urls = val["PatchUrls"].ToObject<List<string>>();
}
else if (val.ContainsKey("DownloadUrls"))
{
    _0024VB_0024Local_Urls = val["DownloadUrls"].ToObject<List<string>>();
}
// ...
_0024VB_0024Local_Extension = "." + PathUtils.GetExtension(
    StringExtensions.BeforeLast(_0024VB_0024Local_Urls.First(), "{CDN}", false));
_0024VB_0024Local_LocalPath = string.Format("{0}{1}.{2}{3}",
    ModMain.RequestTaskTempFolder(), "2.99.0.1", 50, _0024VB_0024Local_Extension);

Task.Output = new ModNet.NetFile[1]
{
    new ModNet.NetFile(_0024VB_0024Local_Urls, _0024VB_0024Local_LocalPath)
}.ToList();
```

`ModNet.NetFile` 的构造参数只有 URL 列表与本地路径，没有哈希/签名。

## 7. 安装：解压覆盖，静默等待重启

```csharp
// PCL/ModSecret.cs:198-211
if (Operators.CompareString(_0024VB_0024Local_Extension, ".zip", false) == 0)
{
    Logger.Info($"解压更新文件：{_0024VB_0024Local_LocalPath}", ...);
    FileUtils.ExtractToDirectory(_0024VB_0024Local_LocalPath, Paths.Base + "PCL\\",
        default(CancellationToken), (ProgressProvider)null);
}
else
{
    Logger.Info($"应用补丁文件：...", ...);
    MsDelta.Apply(ModBase.PathExe, _0024VB_0024Local_LocalPath,
        $"{Paths.Base}PCL\\Plain Craft Launcher 2.exe");
}
if (_0024STATIC_0024UpdateStart_00240212151280E91E_0024IsSilentUpdate)
{
    IsUpdateWaitingRestart = true;
    return;
}
```

## 8. 退出时执行新的 exe

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
        Logger.Info($"更新程序启动，参数：{text}", ...);
        ModBase.StartProcess(new ProcessStartInfo(fileName)
        {
            WindowStyle = ProcessWindowStyle.Hidden,
            CreateNoWindow = true,
            Arguments = text
        });
        if (TriggerRestartAndByEnd)
        {
            ModMain.FrmMain.EndProgram(SendWarning: false);
            Logger.Info("已由于更新强制结束程序", ...);
        }
    }
    catch (Win32Exception ex) { ... }
}
```

## 9. CDN 签名（不是内容签名）

```csharp
// PCL/ModSecret.cs:428-445
internal static string SecretCdnSign(string UrlWithMark)
{
    if (ModBase.ApplicationStartTick < 1)
    {
        return UrlWithMark;
    }
    if (!StringExtensions.EndsWithF(UrlWithMark, "{CDN}", false))
    {
        return UrlWithMark;
    }
    string text = UrlWithMark.Replace("{CDN}", "").Replace(" ", "%20");
    string text2 = StringExtensions.EnsureLength(ModBase.RandomInteger(0, 2147483645).ToString("x"), '0', 8);
    string text3 = Conversions.ToString(ModBase.GetUnixTimestampUtc());
    string text4 = text.Substring(checked(StringExtensions.IndexOfF(text, "://", false) + 3));
    text4 = text4.Substring(StringExtensions.IndexOfF(text4, "/", false));
    string text5 = CryptographyUtils.ComputeHash(EnumerableExtensions.Join((IEnumerable)new string[5]
    {
        text4, text3, text2, "0", "PCL2Server"
    }, "-"), (HashMethod)0);
    return text + (text.Contains("?") ? "&" : "?") + "sign=" +
        EnumerableExtensions.Join((IEnumerable)new string[4] { text3, text2, "0", text5 }, "-");
}
```

密钥 `PCL2Server` 硬编码在客户端，MD5 只覆盖 URL 路径与时间戳，不覆盖响应内容。
