/// 应用设置模型
class AppSettings {
  // 代理端口
  int proxyPort; // mixed-port, 默认7890
  int socksPort; // 默认7891
  int apiPort; // Clash API端口, 默认9090
  String apiSecret; // API密钥

  // 代理模式
  ProxyMode proxyMode;

  // TUN模式
  bool tunMode;
  String tunStack; // gvisor / system / mixed

  // 系统代理
  bool enableSystemProxy;

  // 启动设置
  bool startOnBoot;
  bool startMinimized;
  bool minimizeToTray;
  bool closeToTray;

  // 主题
  bool darkMode;

  // 订阅自动更新
  bool autoUpdateSubscription;
  int updateIntervalHours; // 默认24小时

  // 延迟测试
  String latencyTestUrl;
  int latencyTestTimeout; // 毫秒

  AppSettings({
    this.proxyPort = 7890,
    this.socksPort = 7891,
    this.apiPort = 9090,
    this.apiSecret = '',
    this.proxyMode = ProxyMode.rule,
    this.tunMode = false,
    this.tunStack = 'gvisor',
    this.enableSystemProxy = true,
    this.startOnBoot = false,
    this.startMinimized = false,
    this.minimizeToTray = false,
    this.closeToTray = false,
    this.darkMode = true,
    this.autoUpdateSubscription = true,
    this.updateIntervalHours = 24,
    this.latencyTestUrl = 'http://www.gstatic.com/generate_204',
    this.latencyTestTimeout = 5000,
  });

  Map<String, dynamic> toJson() => {
        'proxyPort': proxyPort,
        'socksPort': socksPort,
        'apiPort': apiPort,
        'apiSecret': apiSecret,
        'proxyMode': proxyMode.name,
        'tunMode': tunMode,
        'tunStack': tunStack,
        'enableSystemProxy': enableSystemProxy,
        'startOnBoot': startOnBoot,
        'startMinimized': startMinimized,
        'minimizeToTray': minimizeToTray,
        'closeToTray': closeToTray,
        'darkMode': darkMode,
        'autoUpdateSubscription': autoUpdateSubscription,
        'updateIntervalHours': updateIntervalHours,
        'latencyTestUrl': latencyTestUrl,
        'latencyTestTimeout': latencyTestTimeout,
      };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        proxyPort: json['proxyPort'] as int? ?? 7890,
        socksPort: json['socksPort'] as int? ?? 7891,
        apiPort: json['apiPort'] as int? ?? 9090,
        apiSecret: json['apiSecret'] as String? ?? '',
        proxyMode: _parseProxyMode(json['proxyMode'] as String?),
        tunMode: json['tunMode'] as bool? ?? false,
        tunStack: json['tunStack'] as String? ?? 'gvisor',
        enableSystemProxy: json['enableSystemProxy'] as bool? ?? true,
        startOnBoot: json['startOnBoot'] as bool? ?? false,
        startMinimized: json['startMinimized'] as bool? ?? false,
        minimizeToTray: json['minimizeToTray'] as bool? ?? false,
        closeToTray: json['closeToTray'] as bool? ?? false,
        darkMode: json['darkMode'] as bool? ?? true,
        autoUpdateSubscription: json['autoUpdateSubscription'] as bool? ?? true,
        updateIntervalHours: json['updateIntervalHours'] as int? ?? 24,
        latencyTestUrl: json['latencyTestUrl'] as String? ??
            'http://www.gstatic.com/generate_204',
        latencyTestTimeout: json['latencyTestTimeout'] as int? ?? 5000,
      );

  static ProxyMode _parseProxyMode(String? mode) {
    switch (mode) {
      case 'global':
        return ProxyMode.global;
      case 'direct':
        return ProxyMode.direct;
      default:
        return ProxyMode.rule;
    }
  }
}

/// 代理模式枚举
enum ProxyMode {
  global('全局模式', 'Global'),
  rule('规则模式', 'Rule'),
  direct('直连模式', 'Direct');

  final String chineseName;
  final String englishName;
  const ProxyMode(this.chineseName, this.englishName);
}
