/// 订阅数据模型
class Subscription {
  final String id;
  String name;
  String url;
  DateTime? lastUpdate;
  bool enabled;
  bool autoUpdate;
  int updateIntervalMinutes;

  Subscription({
    required this.id,
    required this.name,
    required this.url,
    this.lastUpdate,
    this.enabled = true,
    this.autoUpdate = true,
    this.updateIntervalMinutes = 1440, // 默认24小时
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url': url,
        'lastUpdate': lastUpdate?.toIso8601String(),
        'enabled': enabled,
        'autoUpdate': autoUpdate,
        'updateIntervalMinutes': updateIntervalMinutes,
      };

  factory Subscription.fromJson(Map<String, dynamic> json) => Subscription(
        id: json['id'] as String,
        name: json['name'] as String,
        url: json['url'] as String,
        lastUpdate: json['lastUpdate'] != null
            ? DateTime.parse(json['lastUpdate'] as String)
            : null,
        enabled: json['enabled'] as bool? ?? true,
        autoUpdate: json['autoUpdate'] as bool? ?? true,
        updateIntervalMinutes: json['updateIntervalMinutes'] as int? ?? 1440,
      );

  Subscription copyWith({
    String? id,
    String? name,
    String? url,
    DateTime? lastUpdate,
    bool? enabled,
    bool? autoUpdate,
    int? updateIntervalMinutes,
  }) =>
      Subscription(
        id: id ?? this.id,
        name: name ?? this.name,
        url: url ?? this.url,
        lastUpdate: lastUpdate ?? this.lastUpdate,
        enabled: enabled ?? this.enabled,
        autoUpdate: autoUpdate ?? this.autoUpdate,
        updateIntervalMinutes: updateIntervalMinutes ?? this.updateIntervalMinutes,
      );
}
