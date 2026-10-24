# 2.99.0.1 来源与比对

## 用户样本

```text
$ unzip -l "PCL 正式版 2.99.0.1.zip"
 6013952  10-25-2026 00:26   Plain Craft Launcher 2.exe

$ sha256sum "PCL 正式版 2.99.0.1.zip"
4d239a62ed66fb9ebcf4633fd881eb098e9a7e4f296f0e414b58aa2f1f7f7830

$ sha256sum "Plain Craft Launcher 2.exe"
0db34e19d9eeb6d496d20fabe786ec16bbd36ba6b0ccdc8d29cb7e909c114397

$ file "Plain Craft Launcher 2.exe"
PE32 executable for MS Windows 6.00 (GUI), Intel i386 Mono/.Net assembly, 3 sections
```

PE `Security Directory`：RVA = 0，size = 0，即没有 Authenticode 签名。

## 官方仓库

```text
$ git clone --depth 5 https://github.com/Hex-Dragon/PCL2.git upstream
$ git -C upstream log --oneline -3
93ede5d 2.99.0.1 正式版
e3d1cff 2.99.0.1
6b9a50d 2.99.0.0 正式版

$ sha256sum upstream/最新正式版.zip
4d239a62ed66fb9ebcf4633fd881eb098e9a7e4f296f0e414b58aa2f1f7f7830

$ unzip -l upstream/最新正式版.zip
 6013952  10-25-2026 00:26   Plain Craft Launcher 2.exe
```

## 比对

```text
$ unzip -q upstream/最新正式版.zip -d official
$ sha256sum official/"Plain Craft Launcher 2.exe"
0db34e19d9eeb6d496d20fabe786ec16bbd36ba6b0ccdc8d29cb7e909c114397

$ cmp official/"Plain Craft Launcher 2.exe" "Plain Craft Launcher 2.exe"
# 无输出，逐字节一致
```

结论：用户提供的 2.99.0.1 zip 与官方仓库 `93ede5d`（`2.99.0.1 正式版`）中的发布包
逐字节一致，exe 亦一致，不是第三方二次打包。

## 反编译与 diff

```text
$ ilspycmd -p -o decompiled-2991 "Plain Craft Launcher 2.exe"
$ diff -rq decompiled-2990 decompiled-2991
# .cs 19 个不同，.baml 51 个不同，另有 PCL.Resources.resx 和 csproj
```

`e3d1cff` 的公开源码改动（不含二进制 `ModSecret`）：

- 版本号 2.99.0.0 / 413 → 2.99.0.1 / 415；
- 移除 MC 下载入口相关 UI 与报错；
- `PageOtherAbout` 等 UI 调整；
- `ModSecret.vb` 在公开仓库中仍是删减版，不含公告/更新逻辑。
