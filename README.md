# SSRVPN Windows

SSRVPN Windows 是一个基于 Flutter 的绿色免安装代理客户端，内置 Mihomo/Clash Meta 核心，支持系统代理模式和 TUN 模式，适合解压即用、随身携带和多设备复制。

## 功能特性

- 与 Android/macOS 版一致的 SSRVPN UI
- 支持订阅链接、Clash YAML、Base64、`ssr://` 等常见配置格式
- 内置 `mihomo.exe` 代理核心
- 系统代理模式：无需管理员权限，连接时临时修改当前用户代理
- TUN 模式：通过虚拟网卡代理更多流量，需要管理员权限
- 系统托盘：最小化到托盘，右键连接/断开/退出
- 便携数据目录：配置、订阅、缓存和日志默认保存在程序目录
- 程序目录不可写时自动回退到 `%LOCALAPPDATA%\SSRVPN\ssrvpn`
- 在线更新检查

## 环境要求

- Windows 10/11 x64
- Flutter 3.0+
- Visual Studio 2022，需安装 “Desktop development with C++”
- PowerShell 5+

## 快速开始

```powershell
flutter pub get
flutter test
flutter build windows --release
```

Release 输出目录：

```text
build\windows\x64\runner\Release\
```

## 打包绿色版

推荐使用项目内置打包脚本。脚本会执行 Release 构建、整理必需文件、附带 VC++ 运行库并生成 SHA256：

```powershell
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tool\package_windows.ps1
```

最终产物：

```text
SSRVPN_Windows_Release.zip
```

## 便携目录说明

ZIP 解压后大致结构如下：

```text
SSRVPN_Windows/
├── ssrvpn_windows.exe      # 主程序
├── mihomo.exe              # 代理核心
├── ssrvpn/                 # 用户数据，首次运行自动创建
│   ├── settings.json       # 设置
│   ├── subscriptions.json  # 订阅列表
│   ├── config.yaml         # Mihomo 配置
│   ├── ssrvpn.log          # 运行日志
│   └── geoip.metadb        # GeoIP 数据库
├── data/                   # Flutter 运行时资源
└── *.dll                   # 运行依赖
```

可以把整个目录复制到 U 盘或其他电脑直接运行。系统代理恢复快照会单独保存在本机 LocalAppData，避免把一台电脑的代理状态复制到另一台电脑。

## 使用说明

1. 解压 `SSRVPN_Windows_Release.zip`。
2. 双击 `ssrvpn_windows.exe`。
3. 进入「订阅」页面添加订阅地址。
4. 点击刷新，等待节点解析完成。
5. 回到首页选择节点并点击连接。
6. 断开或退出时，应用会尝试恢复连接前的系统代理设置。

## 代理模式

- 系统代理模式：默认模式，无需管理员权限，适合浏览器和遵循系统代理的软件。
- TUN 模式：需要管理员权限，覆盖范围更广，适合不走系统代理的软件。

## Mihomo 核心

便携包内置 `mihomo.exe`。如需自行替换核心，可从 Mihomo Releases 下载兼容版本，重命名为 `mihomo.exe` 后放入 `assets` 目录，再重新打包。

## 项目结构

```text
lib/
├── main.dart                    # Windows 窗口初始化和入口
├── app.dart                     # 应用主框架
├── models/                      # 设置、订阅、节点、代理组模型
├── screens/                     # 首页、订阅、节点编辑、设置页面
├── services/
│   ├── clash_service.dart       # Mihomo 子进程和 REST API 控制
│   ├── system_proxy_service.dart# Windows 系统代理设置和恢复
│   ├── tray_manager.dart        # 系统托盘
│   └── subscription_service.dart# 订阅解析和持久化
├── theme/                       # 主题样式
└── widgets/                     # 通用组件

tool/package_windows.ps1         # 绿色版打包脚本
assets/mihomo.exe                # 代理核心
```

## 测试与验证

```powershell
flutter analyze
flutter test
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass `
  -File .\tool\package_windows.ps1
```

发布前建议人工验证：

- 订阅添加、刷新、删除
- 系统代理连接/断开后恢复
- TUN 模式管理员启动
- 托盘隐藏、显示、退出
- 程序目录不可写时的数据回退

## 常见问题

- 浏览器仍无法联网：确认当前模式是否为系统代理，并检查 Windows 代理设置是否被其他软件覆盖。
- 退出后代理未恢复：重新打开 SSRVPN，应用会尝试恢复上次异常退出留下的代理快照。
- TUN 模式启动失败：以管理员身份运行，并确认系统允许虚拟网卡/驱动。
- 打包失败：确认 Visual Studio C++ 桌面工作负载和 Flutter Windows 桌面支持已安装。

## License

本项目为私有/个人项目时请按仓库实际授权使用；如果公开分发，建议补充明确的开源许可证。
