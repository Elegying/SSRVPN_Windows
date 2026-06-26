@echo off
REM SSRVPN Windows 构建脚本
REM 运行方法：
REM   1. 复制整个 SSRVPN/ 文件夹到 Windows（含 SSRVPN_Windows/ + packages/ssrvpn_shared/）
REM   2. 安装 Flutter SDK + Visual Studio（含"使用C++的桌面开发"）
REM   3. 在 PowerShell 运行：.\SSRVPN_Windows\build_release.bat

cd /d "%~dp0"

echo === 清理旧构建 ===
flutter clean

echo === 获取依赖 ===
flutter pub get

echo === 构建 Release ===
flutter build windows --release

echo === 打包 ZIP ===
powershell -Command "Compress-Archive -Path 'build\windows\x64\runner\Release\*' -DestinationPath 'SSRVPN.zip' -Force"

echo === 完成 ===
dir SSRVPN.zip
echo.
echo ZIP 文件: %CD%\SSRVPN.zip
pause
