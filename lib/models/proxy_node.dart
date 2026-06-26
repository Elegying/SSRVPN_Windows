/// 代理节点模型
class ProxyNode {
  final String name;
  final String type; // ss, ssr, vmess, trojan, etc.
  final String server;
  final int port;
  String group;
  int? latency; // 延迟(毫秒), null表示未测试
  bool isOnline;
  DateTime? lastLatencyTest;
  Map<String, dynamic> extra; // 保存原始配置中的其他字段

  ProxyNode({
    required this.name,
    required this.type,
    required this.server,
    required this.port,
    this.group = '默认',
    this.latency,
    this.isOnline = true,
    this.lastLatencyTest,
    Map<String, dynamic>? extra,
  }) : extra = extra ?? {};

  ProxyNode copyWith({
    String? name,
    String? type,
    String? server,
    int? port,
    String? group,
    int? latency,
    bool? isOnline,
    DateTime? lastLatencyTest,
    Map<String, dynamic>? extra,
  }) =>
      ProxyNode(
        name: name ?? this.name,
        type: type ?? this.type,
        server: server ?? this.server,
        port: port ?? this.port,
        group: group ?? this.group,
        latency: latency ?? this.latency,
        isOnline: isOnline ?? this.isOnline,
        lastLatencyTest: lastLatencyTest ?? this.lastLatencyTest,
        extra: extra ?? Map<String, dynamic>.from(this.extra),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'server': server,
        'port': port,
        'group': group,
        'latency': latency,
        'isOnline': isOnline,
        'lastLatencyTest': lastLatencyTest?.toIso8601String(),
        'extra': extra,
      };

  factory ProxyNode.fromJson(Map<String, dynamic> json) => ProxyNode(
        name: json['name'] as String,
        type: json['type'] as String? ?? 'ss',
        server: json['server'] as String,
        port: int.tryParse(json['port']?.toString() ?? '') ?? 0,
        group: json['group'] as String? ?? '默认',
        latency: json['latency'] as int?,
        isOnline: json['isOnline'] as bool? ?? true,
        lastLatencyTest: json['lastLatencyTest'] != null
            ? DateTime.parse(json['lastLatencyTest'] as String)
            : null,
        extra: json['extra'] != null
            ? Map<String, dynamic>.from(json['extra'] as Map)
            : {},
      );

  /// 延迟颜色等级: 0=绿色(快), 1=黄色(中), 2=红色(慢)
  int get latencyLevel {
    if (latency == null) return 2;
    if (latency! < 200) return 0;
    if (latency! < 500) return 1;
    return 2;
  }

  /// 延迟显示文本
  String get latencyText {
    if (latency == null) return '超时';
    if (latency! < 0) return '超时';
    return '${latency}ms';
  }

  /// 是否为超时节点
  bool get isTimedOut => latency == null || latency! < 0;

  /// 获取用于显示的延迟值（私家车节点强制 23-39ms）
  int? get effectiveLatency {
    if (isTimedOut) return null;
    if (name.contains('私家车')) {
      final seed = name.hashCode.abs();
      return 23 + (seed % 17); // 23 ~ 39
    }
    return latency;
  }

  /// 从Clash YAML配置中的proxy条目创建
  factory ProxyNode.fromYaml(
      String name, Map<String, dynamic> yaml, String group) {
    final type = yaml['type'] as String? ?? 'ss';
    return ProxyNode(
      name: name,
      type: type,
      server: yaml['server'] as String? ?? '',
      port: int.tryParse(yaml['port']?.toString() ?? '') ?? 0,
      group: group,
      extra: Map<String, dynamic>.from(yaml),
    );
  }
}
