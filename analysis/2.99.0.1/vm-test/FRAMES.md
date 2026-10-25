# 逐帧素材位置

最终 take 的原始逐帧保留在本机：

```text
vm/frames/final3/
├── frame-000000.jpg ... frame-001433.jpg   # 1434 张 1920×1080 JPEG
└── index.csv                                # 帧号 + epoch 毫秒 + ISO 时间
```

- 最终视频取帧 **101–1087**（step1 → end+12s），源帧全部保留，未删除。
- 关键帧：101（step1）、554（方法一被拦）、858（方法二 staging）、900（SUCCESS + Calculator）、991（end）。
- 另有 `vm/frames/final`、`vm/frames/final2` 两个布局调试 take，同样保留。
- 本目录的 [`frames-index.csv`](frames-index.csv) 是 `final3/index.csv` 的副本；完整 JPEG 不放进
  `analysis/`，避免仓库膨胀。
