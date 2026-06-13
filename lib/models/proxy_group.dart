import 'proxy_node.dart';

/// 代理组模型 (如 "自动选择", "节点选择" 等)
class ProxyGroup {
  final String name;
  final String type; // select, url-test, fallback, load-balance
  List<ProxyNode> nodes;
  String? selectedNode; // 当前选中的节点名
  int? latency; // 当前选中节点的延迟

  ProxyGroup({
    required this.name,
    required this.type,
    List<ProxyNode>? nodes,
    this.selectedNode,
    this.latency,
  }) : nodes = nodes ?? [];

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type,
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'selectedNode': selectedNode,
        'latency': latency,
      };

  factory ProxyGroup.fromJson(Map<String, dynamic> json) => ProxyGroup(
        name: json['name'] as String,
        type: json['type'] as String? ?? 'select',
        nodes: json['nodes'] != null
            ? (json['nodes'] as List)
                .map((n) => ProxyNode.fromJson(n as Map<String, dynamic>))
                .toList()
            : [],
        selectedNode: json['selectedNode'] as String?,
        latency: json['latency'] as int?,
      );

  /// 从Clash YAML中的proxy-groups条目创建
  factory ProxyGroup.fromYaml(String name, Map<String, dynamic> yaml,
      Map<String, Map<String, dynamic>> allProxies) {
    final type = yaml['type'] as String? ?? 'select';
    final proxies =
        (yaml['proxies'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final nodes = <ProxyNode>[];
    for (final proxyName in proxies) {
      if (allProxies.containsKey(proxyName)) {
        final proxyData = allProxies[proxyName]!;
        nodes.add(ProxyNode.fromYaml(proxyName, proxyData, name));
      }
    }
    return ProxyGroup(
      name: name,
      type: type,
      nodes: nodes,
    );
  }

  int get nodeCount => nodes.length;

  String get latencyText {
    if (latency == null) return 'N/A';
    if (latency! < 0) return '超时';
    return '${latency}ms';
  }
}
