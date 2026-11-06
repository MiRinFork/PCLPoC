# PCL 2.99.0.1 复查（2026-10-25）

## 结论

只补了一半。

2.99.0.1 与远程执行相关的改动只有一处：在公告动作“写设置”之前加了一份 12 个键的黑名单。命中黑名单时，整个动作失败。

这挡住了“启动前命令”那条链，但没有改变“静默更新”那条链：更新地址仍来自远程配置，下载的包仍没有签名或哈希校验，退出时仍会执行。

## 样本

`PCL 正式版 2.99.0.1.zip`

SHA-256 `4d239a62ed66fb9ebcf4633fd881eb098e9a7e4f296f0e414b58aa2f1f7f7830`

里面 `Plain Craft Launcher 2.exe`

SHA-256 `0db34e19d9eeb6d496d20fabe786ec16bbd36ba6b0ccdc8d29cb7e909c114397`

与官方仓库 `93ede5d`（2.99.0.1 正式版）的发布包逐字节一致，不是第三方二次打包。

## 改动

对 2.99.0.0 与 2.99.0.1 做了静态比对，并在隔离的 Windows 虚拟机里做了动态验证。

与远程执行相关的差异只有设置写入前的黑名单：

```text
写设置(key, value):
    if key in BLACKLIST:   # 12 个已知键
        raise Rejected
    settings[key] = value
```

黑名单是枚举式的，只能挡住已知键，没有从能力上限制“公告可以写设置”。

## 两条链的现状

- 启动前命令：被黑名单拦截，当前版本下不可达。
- 静默更新：仍可从远程配置取得下载地址，下载的包没有签名/哈希校验，退出时执行。动态验证确认仍然可达。

## 建议

同主报告：固定更新源，校验签名或哈希，并在更新前告知用户。

## 样本哈希（对照）

```text
4d239a62ed66fb9ebcf4633fd881eb098e9a7e4f296f0e414b58aa2f1f7f7830  PCL 正式版 2.99.0.1.zip
0db34e19d9eeb6d496d20fabe786ec16bbd36ba6b0ccdc8d29cb7e909c114397  Plain Craft Launcher 2.exe (2.99.0.1)
4d239a62ed66fb9ebcf4633fd881eb098e9a7e4f296f0e414b58aa2f1f7f7830  upstream/最新正式版.zip (Hex-Dragon/PCL2 93ede5d)

6b6e1260cb5a1d6a303855f1c60cab3d0bc1aebba7e40a964180188b271e7386  Plain Craft Launcher 2.exe (2.99.0.0)
01877f06df84cbab376c286a633e76ef7fca0bb469e26df97f3b09b5abd503bc  upstream/最新正式版.zip (Hex-Dragon/PCL2 6b9a50d)
```
