# Isshin Player

极简 iOS 视频播放器（自用）。需求见 `需求.txt` / `PRD.md`。

## 打开工程

本机需安装 **完整 Xcode**（仅 Command Line Tools 无法编译）。

```bash
open IsshinPlayer.xcodeproj
```

1. Signing & Capabilities → 选你的个人 Team（免费 Apple ID 即可）
2. 真机或模拟器 Run

## 已实现（MVP）

- 相册多选导入视频 → 播放列表
- 播放 / 暂停 / 进度 seek
- 倍速 0.5x–2x
- 画中画（系统支持时）
- 后台 / 锁屏续播 + 控制中心（含上下首）
- 固定暗黑主题；Empty / Loading / Error

## 结构

```
IsshinPlayer/
  App/
  Core/Theme|Audio|PiP/
  Features/Player/
  DesignSystem/
```
