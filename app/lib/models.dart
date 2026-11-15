/// The JSON models of the core API. The window is a thin client: every value
/// it shows comes from one of these objects.
library;

class TunnelState {
  const TunnelState({
    this.running = false,
    this.address = '',
    this.subnet = '',
    this.publicKey = '',
    this.peersUp = 0,
    this.peersTotal = 0,
    this.rxBytes = 0,
    this.txBytes = 0,
    this.openConnections = 0,
    this.totalConnections = 0,
    this.exitEnabled = false,
    this.exitName = '',
    this.exitState = '',
    this.exitDns = '',
    this.proxyHttp = '',
    this.proxySocks = '',
    this.systemProxy = false,
    this.systemProxyAddress = '',
    this.lastError = '',
    this.version = '',
    this.platform = '',
    this.yggVersion = '',
    this.uptimeSeconds = 0,
  });

  final bool running;
  final String address;
  final String subnet;
  final String publicKey;
  final int peersUp;
  final int peersTotal;
  final int rxBytes;
  final int txBytes;
  final int openConnections;
  final int totalConnections;
  final bool exitEnabled;
  final String exitName;
  final String exitState;
  final String exitDns;
  final String proxyHttp;
  final String proxySocks;
  final bool systemProxy;
  final String systemProxyAddress;
  final String lastError;
  final String version;
  final String platform;
  final String yggVersion;
  final int uptimeSeconds;

  factory TunnelState.fromJson(Map<String, dynamic> json) => TunnelState(
    running: json['running'] as bool? ?? false,
    address: json['address'] as String? ?? '',
    subnet: json['subnet'] as String? ?? '',
    publicKey: json['publicKey'] as String? ?? '',
    peersUp: (json['peersUp'] as num?)?.toInt() ?? 0,
    peersTotal: (json['peersTotal'] as num?)?.toInt() ?? 0,
    rxBytes: (json['rxBytes'] as num?)?.toInt() ?? 0,
    txBytes: (json['txBytes'] as num?)?.toInt() ?? 0,
    openConnections: (json['openConnections'] as num?)?.toInt() ?? 0,
    totalConnections: (json['totalConnections'] as num?)?.toInt() ?? 0,
    exitEnabled: json['exitEnabled'] as bool? ?? false,
    exitName: json['exitName'] as String? ?? '',
    exitState: json['exitState'] as String? ?? '',
    exitDns: json['exitDns'] as String? ?? '',
    proxyHttp: json['proxyHttp'] as String? ?? '',
    proxySocks: json['proxySocks'] as String? ?? '',
    systemProxy: json['systemProxy'] as bool? ?? false,
    systemProxyAddress: json['systemProxyAddress'] as String? ?? '',
    lastError: json['lastError'] as String? ?? '',
    version: json['version'] as String? ?? '',
    platform: json['platform'] as String? ?? '',
    yggVersion: json['yggVersion'] as String? ?? '',
    uptimeSeconds: (json['uptimeSeconds'] as num?)?.toInt() ?? 0,
  );
}

class PeerStatus {
  const PeerStatus({
    required this.uri,
    this.up = false,
    this.inbound = false,
    this.latencyMs = 0,
    this.rxBytes = 0,
    this.txBytes = 0,
    this.ip = '',
    this.lastError = '',
  });

  final String uri;
  final bool up;
  final bool inbound;
  final double latencyMs;
  final int rxBytes;
  final int txBytes;
  final String ip;
  final String lastError;

  factory PeerStatus.fromJson(Map<String, dynamic> json) => PeerStatus(
    uri: json['uri'] as String? ?? '',
    up: json['up'] as bool? ?? false,
    inbound: json['inbound'] as bool? ?? false,
    latencyMs: (json['latencyMs'] as num?)?.toDouble() ?? 0,
    rxBytes: (json['rxBytes'] as num?)?.toInt() ?? 0,
    txBytes: (json['txBytes'] as num?)?.toInt() ?? 0,
    ip: json['ip'] as String? ?? '',
    lastError: json['lastError'] as String? ?? '',
  );
}

class ExitProfile {
  const ExitProfile({
    required this.id,
    required this.name,
    required this.address,
    this.socksPort = 1080,
    this.apiPort = 1080,
    this.token = '',
    this.peer = '',
    this.dns = '',
    this.dnsPort = 53,
  });

  final String id;
  final String name;
  final String address;
  final int socksPort;
  final int apiPort;
  final String token;
  final String peer;
  final String dns;
  final int dnsPort;

  factory ExitProfile.fromJson(Map<String, dynamic> json) => ExitProfile(
    id: json['id'] as String? ?? '',
    name: json['name'] as String? ?? '',
    address: json['address'] as String? ?? '',
    socksPort: (json['socksPort'] as num?)?.toInt() ?? 1080,
    apiPort: (json['apiPort'] as num?)?.toInt() ?? 1080,
    token: json['token'] as String? ?? '',
    peer: json['peer'] as String? ?? '',
    dns: json['dns'] as String? ?? '',
    dnsPort: (json['dnsPort'] as num?)?.toInt() ?? 53,
  );
}

class LogLine {
  const LogLine({required this.time, required this.level, required this.message});

  final DateTime time;
  final String level;
  final String message;

  factory LogLine.fromJson(Map<String, dynamic> json) => LogLine(
    time: DateTime.tryParse(json['time'] as String? ?? '')?.toLocal() ?? DateTime.now(),
    level: json['level'] as String? ?? 'info',
    message: json['message'] as String? ?? '',
  );
}

/// The editable part of the core configuration. The window keeps every field
/// as text, so an invalid port can be shown instead of silently dropped.
class CoreConfig {
  CoreConfig({
    this.bind = '127.0.0.1',
    this.httpPort = '7890',
    this.socksPort = '7891',
    this.mtu = '1280',
    this.yggDns = '',
    this.systemDns = '',
    this.exitDns = '',
    this.fallbackDirect = true,
    this.localDns = true,
    this.systemProxy = false,
    this.autoConnect = false,
  });

  String bind;
  String httpPort;
  String socksPort;
  String mtu;
  String yggDns;
  String systemDns;
  String exitDns;
  bool fallbackDirect;
  bool localDns;
  bool systemProxy;
  bool autoConnect;

  factory CoreConfig.fromJson(Map<String, dynamic> json) => CoreConfig(
    bind: json['bind'] as String? ?? '127.0.0.1',
    httpPort: '${json['httpPort'] ?? 7890}',
    socksPort: '${json['socksPort'] ?? 7891}',
    mtu: '${json['mtu'] ?? 1280}',
    yggDns: ((json['yggDns'] as List?) ?? const []).join(', '),
    systemDns: ((json['systemDns'] as List?) ?? const []).join(', '),
    exitDns: ((json['exitDns'] as List?) ?? const []).join(', '),
    fallbackDirect: json['exitFallbackDirect'] as bool? ?? true,
    localDns: json['localDns'] as bool? ?? true,
    systemProxy: json['systemProxy'] as bool? ?? false,
    autoConnect: json['autoConnect'] as bool? ?? false,
  );

  Map<String, dynamic> toJson({
    required String privateKey,
    required List<String> peers,
    required List<ExitProfile> exits,
    required String activeId,
    required bool exitEnabled,
  }) => {
    'privateKey': privateKey,
    'peers': peers,
    'mtu': int.tryParse(mtu.trim()) ?? 1280,
    'bind': bind.trim(),
    'httpPort': int.tryParse(httpPort.trim()) ?? 7890,
    'socksPort': int.tryParse(socksPort.trim()) ?? 7891,
    'exitEnabled': exitEnabled,
    'exitActiveId': activeId,
    'exitProfiles': [
      for (final profile in exits)
        {
          'id': profile.id,
          'name': profile.name,
          'address': profile.address,
          'socksPort': profile.socksPort,
          'apiPort': profile.apiPort,
          if (profile.token.isNotEmpty) 'token': profile.token,
          if (profile.peer.isNotEmpty) 'peer': profile.peer,
          if (profile.dns.isNotEmpty) 'dns': profile.dns,
          if (profile.dnsPort != 53) 'dnsPort': profile.dnsPort,
        },
    ],
    'exitFallbackDirect': fallbackDirect,
    'exitDns': splitList(exitDns),
    'yggDns': splitList(yggDns),
    'systemDns': splitList(systemDns),
    'localDns': localDns,
    'systemProxy': systemProxy,
    'autoConnect': autoConnect,
  };
}

List<String> splitList(String value) => [
  for (final item in value.split(RegExp(r'[,;\s]+')))
    if (item.trim().isNotEmpty) item.trim(),
];

String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var value = bytes / 1024;
  var index = 0;
  while (value >= 1024 && index < units.length - 1) {
    value /= 1024;
    index++;
  }
  return '${value.toStringAsFixed(1)} ${units[index]}';
}

String formatUptime(int seconds) {
  if (seconds <= 0) return '—';
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${seconds % 60}s';
  return '${seconds}s';
}
