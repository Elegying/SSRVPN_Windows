import 'dart:io';
import 'dart:ffi';
import 'package:ffi/ffi.dart';

/// Windows系统代理服务
class SystemProxyService {
  static final SystemProxyService _instance = SystemProxyService._();
  factory SystemProxyService() => _instance;
  SystemProxyService._();

  bool _proxyEnabled = false;
  bool get isProxyEnabled => _proxyEnabled;

  Future<bool> setSystemProxy(String host, int port) async {
    if (!Platform.isWindows) return false;
    try {
      // 禁用WPAD自动代理检测（会覆盖手动设置）
      await Process.run('reg', ['add', 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings', '/v', 'AutoDetect', '/t', 'REG_DWORD', '/d', '0', '/f']);
      await Process.run('reg', ['add', 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings', '/v', 'AutoConfigURL', '/t', 'REG_SZ', '/d', '', '/f']);
      // 设置代理
      await Process.run('reg', ['add', 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings', '/v', 'ProxyServer', '/t', 'REG_SZ', '/d', '$host:$port', '/f']);
      await Process.run('reg', ['add', 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings', '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f']);
      _notifySystem();
      _proxyEnabled = true;
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> clearSystemProxy() async {
    if (!Platform.isWindows) return false;
    try {
      await Process.run('reg', ['add', 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings', '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f']);
      await Process.run('reg', ['add', 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings', '/v', 'ProxyServer', '/t', 'REG_SZ', '/d', '', '/f']);
      // 恢复WPAD自动检测
      await Process.run('reg', ['add', 'HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Internet Settings', '/v', 'AutoDetect', '/t', 'REG_DWORD', '/d', '1', '/f']);
      _notifySystem();
      _proxyEnabled = false;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 通知Windows代理设置已变更
  void _notifySystem() {
    try {
      final wininet = DynamicLibrary.open('wininet.dll');
      final opt = wininet.lookupFunction<
        Uint32 Function(IntPtr, Uint32, Pointer<Void>, Uint32),
        int Function(int, int, Pointer<Void>, int)
      >('InternetSetOptionW');
      final nullPtr = Pointer<Void>.fromAddress(0);
      opt(0, 39, nullPtr, 0); // SETTINGS_CHANGED
      opt(0, 37, nullPtr, 0); // REFRESH
    } catch (_) {}
  }
}
