<img align="center" src="macast_slogan.png" alt="slogan" height="auto"/>

# mac-cast (Macast - anyi11 优化版)

<p align="left">
  <a href="https://github.com/anyi11/mac-cast/releases/latest">
    <img src="https://img.shields.io/github/downloads/anyi11/mac-cast/total?color=blue&logo=github" alt="downloads" />
  </a>
  <a href="https://github.com/anyi11/mac-cast/releases/latest">
    <img src="https://img.shields.io/badge/MacOS-13.0%20and%20higher-lightgrey?logo=Apple" alt="mac" />
  </a>
  <a href="https://github.com/anyi11/mac-cast">
    <img src="https://img.shields.io/badge/License-GPL--3.0-green" alt="license" />
  </a>
</p>

`mac-cast` 是一个专为 macOS 深度优化的 **菜单栏\状态栏** 投屏接收端应用。支持手机端（Bilibili、爱优腾、网易云音乐等）通过标准 DLNA 协议，一键将视频、音乐、图片投放到 Mac 电脑端播放。

基于原开源项目进行深度定制与性能升级，带来极致丝滑、美观、低延迟的本地化播放与控制体验。

---

## 🚀 核心优化与改动对比

| 功能特性 | 官方原版 Macast | mac-cast (本优化版) | 优化说明 |
| :--- | :---: | :---: | :--- |
| **状态栏主菜单** | 包含 Friendly Name 输入卡片，略显繁杂 | 极简设计，仅保留运行状态与播放控制器 | 界面更清爽，符合 macOS 规范 |
| **播放控制器 (OSC)** | 官方简易版本 (拖动易卡死) | 升级版 ModernZ OSC (中文化) | 界面精致，触控按钮增大 25%，操作更精准 |
| **进度条拖拽** | 频繁发送请求导致播放极其卡顿 | 鼠标释放一次性 seek (无缝过渡) | 极大提升了播放控制的流畅度 |
| **显示高刷支持** | 锁帧 / 60Hz 限制 | 适配 ProMotion 120Hz 高刷新率 | 拖拽和弹窗动画如丝般顺滑 |
| **设置与配置** | Web 页面 / 简易面板 | 独立 native 设置窗口 (大小/位置映射完全修复) | 修复「全屏」误触发「自动」的映射 Bug |
| **日志与下载记录** | 历史累积，体积过大易引发卡顿 | 自动滚动清理，上限 50 条 | 保证长期运行不占磁盘、不降速 |
| **应用体积瘦身** | 应用 97MB / 发布包 41MB | 应用 **71MB** / 发布包 **28MB** | 剔除无用脚本、冗余二进制与测试依赖，发布包减小 31% |
| **按需启动/自动关闭** | 启动软件时直接开窗，关闭后又反复弹起 | 软件启动时不自动开窗，首投按需唤醒；手动关闭后不重复弹出 | 精简后台逻辑，防止无用弹窗打扰 |

---

## 📸 软件界面预览

### 1. 状态栏主菜单与播放控制卡片
<img align="center" width="400" src="docs/images/popover_mockup.png" alt="Popover UI" height="auto"/>

### 2. 独立设置窗口 (通用设置与播放器配置)
<img align="center" width="450" src="docs/images/settings_mockup.png" alt="Settings UI" height="auto"/>

### 3. 全新中文化 ModernZ 播放器控制面板
<img align="center" width="600" src="docs/images/player_mockup.png" alt="Player OSC UI" height="auto"/>

---

## 📖 使用指南

### 1. 安装与启动
* 点击前往 [mac-cast GitHub Releases](https://github.com/anyi11/mac-cast/releases/latest) 下载最新的 `mac-cast.dmg` 或编译好的 `Macast.app`，直接拖入「应用程序」即可运行。
* 首次打开时，状态栏（屏幕右上角）会显现一个投屏接收图标。

### 2. 手机端投屏操作
* 确保您的 Mac 电脑和手机连接在 **同一个 Wi-Fi（局域网）** 下。
* 打开手机端支持投屏的 App（如：哔哩哔哩、爱奇艺、腾讯视频、优酷、网易云音乐等），播放任意视频。
* 点击视频画面右上角的 **投屏图标 (TV)**，在弹出的设备列表中选择 `mac-cast`（默认名称为 `客厅的Mac`，可在设置中自由更改）。
* 视频将在您的 Mac 电脑上通过内置的 MPV 播放器自动全屏/窗口播放。

---

## 🛠️ 自源码构建与定制

如果您是开发者，可以通过以下简单命令在本地构建 `mac-cast`：

```shell
# 克隆仓库
git clone https://github.com/anyi11/mac-cast.git
cd mac-cast

# 执行构建脚本 (将自动完成 Swift 编译、目录创建和资源拷贝)
bash build_app.sh
```
构建成功后，会在项目根目录下生成最新的 `Macast.app` 安装包。

### 3. 自动发布 Release (CI/CD)
项目集成了 GitHub Actions 自动化工作流。每当您在本地打上版本标签（如 `v1.2.5`）并推送时，GitHub 将自动编译、打包并发布对应的 Release 附件：
```shell
# 1. 本地打上版本标签
git tag v1.2.5

# 2. 推送标签到 GitHub
git push origin v1.2.5
```

---

## 💡 常见问题排查 (FAQ)

#### Q1: 手机搜不到电脑设备？
* **防火墙拦截**：请在 Mac 的 `系统设置 -> 键盘/网络/安全性` 中检查防火墙，确保允许 `MacastUI` 接收本地网络连接。
* **双频 Wi-Fi 隔离**：部分路由器开启了「AP隔离」或手机在 5G 频段而电脑在 2.4G 频段导致无法互通，请确保两者在同一局域网网段内。
* **尝试手动检查**：在手机浏览器中输入 `http://<你的电脑IP>:1068`，若显示 Hello World 则说明网络已通，请检查手机 App 权限。

#### Q2: 怎么修改默认播放器或设置硬件解码？
* 点击状态栏图标 -> 点击 **「设置 (Gear 图标)」**，即可在弹出的原生窗口中开启/关闭硬件解码，修改保存后应用会自动重启服务应用生效。
