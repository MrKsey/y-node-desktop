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
    this.exitInUse = false,
    this.exitName = '',
    this.exitState = '',
    this.exitDns = '',
    this.exitFlag = '',
    this.exitCountry = '',
    this.exitCity = '',
    this.latencyMs = 0,
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
  final bool exitInUse;
  final String exitName;
  final String exitState;
  final String exitDns;
  final String exitFlag;
  final String exitCountry;
  final String exitCity;
  final double latencyMs;
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
    exitInUse: json['exitInUse'] as bool? ?? false,
    exitName: json['exitName'] as String? ?? '',
    exitState: json['exitState'] as String? ?? '',
    exitDns: json['exitDns'] as String? ?? '',
    exitFlag: json['exitFlag'] as String? ?? '',
    exitCountry: json['exitCountry'] as String? ?? '',
    exitCity: json['exitCity'] as String? ?? '',
    latencyMs: (json['latencyMs'] as num?)?.toDouble() ?? 0,
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
    this.invite = '',
    this.registered = false,
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
  final String invite;
  final bool registered;
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
    invite: json['invite'] as String? ?? '',
    registered: json['registered'] as bool? ?? false,
    peer: json['peer'] as String? ?? '',
    dns: json['dns'] as String? ?? '',
    dnsPort: (json['dnsPort'] as num?)?.toInt() ?? 53,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'address': address,
    'socksPort': socksPort,
    'apiPort': apiPort,
    if (token.isNotEmpty) 'token': token,
    if (invite.isNotEmpty) 'invite': invite,
    if (registered) 'registered': true,
    if (peer.isNotEmpty) 'peer': peer,
    if (dns.isNotEmpty) 'dns': dns,
    if (dnsPort != 53) 'dnsPort': dnsPort,
  };
}

/// One resolver of the Yggdrasil wiki, listed under "Available servers".
class DnsPreset {
  const DnsPreset({required this.address, this.location = '', this.note = ''});

  final String address;
  final String location;
  final String note;

  factory DnsPreset.fromJson(Map<String, dynamic> json) => DnsPreset(
    address: json['address'] as String? ?? '',
    location: json['location'] as String? ?? '',
    note: json['note'] as String? ?? '',
  );

  String get label =>
      [location, note].where((part) => part.isNotEmpty).join(' · ');
}

/// One row of the last latency test, stored by the core.
class ProbeEntry {
  const ProbeEntry({
    required this.uri,
    this.up = false,
    this.latencyMs = 0,
    this.error = '',
  });

  final String uri;
  final bool up;
  final double latencyMs;
  final String error;

  factory ProbeEntry.fromJson(Map<String, dynamic> json) => ProbeEntry(
    uri: json['uri'] as String? ?? '',
    up: json['up'] as bool? ?? false,
    latencyMs: (json['latencyMs'] as num?)?.toDouble() ?? 0,
    error: json['error'] as String? ?? '',
  );
}

/// One user-added entry of the Services page. The built-in catalogue is part of
/// the window and is not stored here.
class ServiceEntry {
  const ServiceEntry({
    this.id = '',
    required this.title,
    required this.url,
    this.description = '',
    this.builtIn = false,
  });

  final String id;
  final String title;
  final String url;
  final String description;
  final bool builtIn;

  factory ServiceEntry.fromJson(Map<String, dynamic> json) => ServiceEntry(
    id: json['id'] as String? ?? '',
    title: json['title'] as String? ?? '',
    url: json['url'] as String? ?? '',
    description: json['description'] as String? ?? '',
    builtIn: json['builtIn'] as bool? ?? false,
  );

  Map<String, dynamic> toJson() => {
    if (id.isNotEmpty) 'id': id,
    'title': title,
    'url': url,
    if (description.isNotEmpty) 'description': description,
  };
}

/// One row of the public peer list with the place it belongs to.
class CatalogPeer {
  const CatalogPeer({
    required this.uri,
    this.host = '',
    this.country = '',
    this.countryName = '',
    this.flag = '',
    this.city = '',
    this.scheme = '',
    this.port = 0,
  });

  final String uri;
  final String host;
  final String country;
  final String countryName;
  final String flag;
  final String city;
  final String scheme;
  final int port;

  factory CatalogPeer.fromJson(Map<String, dynamic> json) => CatalogPeer(
    uri: json['uri'] as String? ?? '',
    host: json['host'] as String? ?? '',
    country: json['country'] as String? ?? '',
    countryName: json['countryName'] as String? ?? '',
    flag: json['flag'] as String? ?? '',
    city: json['city'] as String? ?? '',
    scheme: json['scheme'] as String? ?? '',
    port: (json['port'] as num?)?.toInt() ?? 0,
  );
}

/// A country of the catalogue, used by the filter of the peer browser.
class CountryCount {
  const CountryCount({
    required this.slug,
    required this.name,
    this.flag = '',
    this.count = 0,
  });

  final String slug;
  final String name;
  final String flag;
  final int count;

  factory CountryCount.fromJson(Map<String, dynamic> json) => CountryCount(
    slug: json['slug'] as String? ?? '',
    name: json['name'] as String? ?? '',
    flag: json['flag'] as String? ?? '',
    count: (json['count'] as num?)?.toInt() ?? 0,
  );
}

/// Where the user is, as far as GeoIP can tell.
class GeoLocation {
  const GeoLocation({
    this.countryCode = '',
    this.countrySlug = '',
    this.countryName = '',
    this.flag = '',
    this.city = '',
    this.lat = 0,
    this.lon = 0,
    this.source = '',
  });

  final String countryCode;
  final String countrySlug;
  final String countryName;
  final String flag;
  final String city;
  final double lat;
  final double lon;
  final String source;

  factory GeoLocation.fromJson(Map<String, dynamic> json) => GeoLocation(
    countryCode: json['countryCode'] as String? ?? '',
    countrySlug: json['countrySlug'] as String? ?? '',
    countryName: json['countryName'] as String? ?? '',
    flag: json['flag'] as String? ?? '',
    city: json['city'] as String? ?? '',
    lat: (json['lat'] as num?)?.toDouble() ?? 0,
    lon: (json['lon'] as num?)?.toDouble() ?? 0,
    source: json['source'] as String? ?? '',
  );
}

/// The answer of the catalogue endpoint.
class PeerCatalog {
  const PeerCatalog({
    this.peers = const [],
    this.countries = const [],
    this.detected = const GeoLocation(),
    this.country = '',
    this.updated,
  });

  final List<CatalogPeer> peers;
  final List<CountryCount> countries;
  final GeoLocation detected;
  final String country;
  final DateTime? updated;

  factory PeerCatalog.fromJson(Map<String, dynamic> json) => PeerCatalog(
    peers: [
      for (final item in (json['peers'] as List? ?? const []))
        if (item is Map<String, dynamic>) CatalogPeer.fromJson(item),
    ],
    countries: [
      for (final item in (json['countries'] as List? ?? const []))
        if (item is Map<String, dynamic>) CountryCount.fromJson(item),
    ],
    detected: json['detected'] is Map<String, dynamic>
        ? GeoLocation.fromJson(json['detected'] as Map<String, dynamic>)
        : const GeoLocation(),
    country: json['country'] as String? ?? '',
    updated: DateTime.tryParse(json['updated'] as String? ?? ''),
  );
}

/// The address a remote service sees for this device.
class PublicIpResult {
  const PublicIpResult({
    this.ok = false,
    this.ip = '',
    this.via = '',
    this.ms = 0,
    this.error = '',
  });

  final bool ok;
  final String ip;
  final String via;
  final double ms;
  final String error;

  factory PublicIpResult.fromJson(Map<String, dynamic> json) => PublicIpResult(
    ok: json['ok'] as bool? ?? false,
    ip: json['ip'] as String? ?? '',
    via: json['via'] as String? ?? '',
    ms: (json['ms'] as num?)?.toDouble() ?? 0,
    error: json['error'] as String? ?? '',
  );
}

/// One stage of the UDP or the IPv6 check of the exit node.
class ExitProbeStage {
  const ExitProbeStage({
    this.ok = false,
    this.skipped = false,
    this.latencyMs = 0,
    this.target = '',
    this.server = '',
    this.version = '',
    this.address = '',
    this.error = '',
  });

  final bool ok;
  final bool skipped;
  final double latencyMs;
  final String target;
  final String server;
  final String version;
  final String address;
  final String error;

  factory ExitProbeStage.fromJson(Map<String, dynamic> json) => ExitProbeStage(
    ok: json['ok'] as bool? ?? false,
    skipped: json['skipped'] as bool? ?? false,
    latencyMs: (json['latencyMs'] as num?)?.toDouble() ?? 0,
    target: json['target'] as String? ?? '',
    server: json['server'] as String? ?? '',
    version: json['version'] as String? ?? '',
    address: json['address'] as String? ?? '',
    error: json['error'] as String? ?? '',
  );
}

/// The result of the UDP relay check (DNS and the QUIC handshake).
class ExitUdpProbe {
  const ExitUdpProbe({
    this.ok = false,
    this.state = '',
    this.profile = '',
    this.udp = const ExitProbeStage(),
    this.quic = const ExitProbeStage(),
    this.datagramsOut = 0,
    this.datagramsIn = 0,
    this.durationMs = 0,
    this.error = '',
  });

  final bool ok;
  final String state;
  final String profile;
  final ExitProbeStage udp;
  final ExitProbeStage quic;
  final int datagramsOut;
  final int datagramsIn;
  final int durationMs;
  final String error;

  factory ExitUdpProbe.fromJson(Map<String, dynamic> json) => ExitUdpProbe(
    ok: json['ok'] as bool? ?? false,
    state: json['state'] as String? ?? '',
    profile: json['profile'] as String? ?? '',
    udp: json['udp'] is Map<String, dynamic>
        ? ExitProbeStage.fromJson(json['udp'] as Map<String, dynamic>)
        : const ExitProbeStage(),
    quic: json['quic'] is Map<String, dynamic>
        ? ExitProbeStage.fromJson(json['quic'] as Map<String, dynamic>)
        : const ExitProbeStage(),
    datagramsOut: (json['datagramsOut'] as num?)?.toInt() ?? 0,
    datagramsIn: (json['datagramsIn'] as num?)?.toInt() ?? 0,
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    error: json['error'] as String? ?? '',
  );
}

/// The result of the IPv6 check of the exit node.
class ExitIpv6Probe {
  const ExitIpv6Probe({
    this.ok = false,
    this.state = '',
    this.profile = '',
    this.tcp = const ExitProbeStage(),
    this.udp = const ExitProbeStage(),
    this.durationMs = 0,
    this.error = '',
  });

  final bool ok;
  final String state;
  final String profile;
  final ExitProbeStage tcp;
  final ExitProbeStage udp;
  final int durationMs;
  final String error;

  factory ExitIpv6Probe.fromJson(Map<String, dynamic> json) => ExitIpv6Probe(
    ok: json['ok'] as bool? ?? false,
    state: json['state'] as String? ?? '',
    profile: json['profile'] as String? ?? '',
    tcp: json['tcp'] is Map<String, dynamic>
        ? ExitProbeStage.fromJson(json['tcp'] as Map<String, dynamic>)
        : const ExitProbeStage(),
    udp: json['udp'] is Map<String, dynamic>
        ? ExitProbeStage.fromJson(json['udp'] as Map<String, dynamic>)
        : const ExitProbeStage(),
    durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
    error: json['error'] as String? ?? '',
  );
}

class LogLine {
  const LogLine({
    required this.time,
    required this.level,
    required this.message,
  });

  final DateTime time;
  final String level;
  final String message;

  factory LogLine.fromJson(Map<String, dynamic> json) => LogLine(
    time:
        DateTime.tryParse(json['time'] as String? ?? '')?.toLocal() ??
        DateTime.now(),
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
    this.yggDns = '308:84:68:55::, 308:62:45:62::',
    this.systemDns = '',
    this.exitDns = '',
    this.fallbackDirect = true,
    this.localDns = true,
    this.systemProxy = true,
    this.autoConnect = false,
    this.dnsMode = 'yggdrasil',
    this.exitDnsEnabled = true,
    this.exitUdp = true,
    this.ipv6 = 'auto',
    this.exitLabelEnabled = false,
    this.exitLabel = '',
    this.peerCount = '3',
    this.peerAutoReplace = true,
    this.peerDeadTimeoutSec = '90',
    this.peerCheckIntervalSec = '30',
    this.theme = 'auto',
    this.closeToTray = true,
    this.minimizeToTray = false,
    this.updateCheck = false,
    this.updateNotified = '',
    this.countrySlug = '',
    this.loggingDisabled = false,
    this.services = const [],
    this.hiddenServices = const [],
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
  String dnsMode;
  bool exitDnsEnabled;
  bool exitUdp;
  String ipv6;
  bool exitLabelEnabled;
  String exitLabel;
  String peerCount;
  bool peerAutoReplace;
  String peerDeadTimeoutSec;
  String peerCheckIntervalSec;
  String theme;
  bool closeToTray;
  bool minimizeToTray;
  bool updateCheck;
  String updateNotified;
  String countrySlug;
  bool loggingDisabled;
  List<ServiceEntry> services;

  /// The built-in resources the user deleted. The core owns this list: the
  /// window only reads it, so a settings change never brings them back.
  List<String> hiddenServices;

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
    systemProxy: json['systemProxy'] as bool? ?? true,
    autoConnect: json['autoConnect'] as bool? ?? false,
    dnsMode: json['dnsMode'] as String? ?? 'yggdrasil',
    exitDnsEnabled: json['exitDnsEnabled'] as bool? ?? true,
    exitUdp: json['exitUdp'] as bool? ?? true,
    ipv6: json['ipv6'] as String? ?? 'auto',
    exitLabelEnabled: json['exitLabelEnabled'] as bool? ?? false,
    exitLabel: json['exitLabel'] as String? ?? '',
    peerCount: '${json['peerCount'] ?? 3}',
    peerAutoReplace: json['peerAutoReplace'] as bool? ?? true,
    peerDeadTimeoutSec: _secondsOf(json['peerDeadTimeout'], 90),
    peerCheckIntervalSec: _secondsOf(json['peerCheckInterval'], 30),
    theme: json['theme'] as String? ?? 'auto',
    closeToTray: json['closeToTray'] as bool? ?? true,
    minimizeToTray: json['minimizeToTray'] as bool? ?? false,
    updateCheck: json['updateCheck'] as bool? ?? false,
    updateNotified: json['updateNotified'] as String? ?? '',
    countrySlug: json['countrySlug'] as String? ?? '',
    loggingDisabled: json['loggingDisabled'] as bool? ?? false,
    services: [
      for (final item in (json['services'] as List? ?? const []))
        ServiceEntry.fromJson(item as Map<String, dynamic>),
    ],
    hiddenServices: [
      for (final item in (json['hiddenServices'] as List? ?? const [])) '$item',
    ],
  );

  Map<String, dynamic> toJson({
    required String privateKey,
    required List<String> peers,
    List<String> pool = const [],
    required List<ExitProfile> exits,
    required String activeId,
    required bool exitEnabled,
  }) => {
    'privateKey': privateKey,
    'peers': peers,
    'pool': pool,
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
          if (profile.invite.isNotEmpty) 'invite': profile.invite,
          if (profile.registered) 'registered': true,
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
    'dnsMode': dnsMode,
    'exitDnsEnabled': exitDnsEnabled,
    'exitUdp': exitUdp,
    'ipv6': ipv6,
    'exitLabelEnabled': exitLabelEnabled,
    'exitLabel': exitLabel,
    'peerCount': int.tryParse(peerCount.trim()) ?? 3,
    'peerAutoReplace': peerAutoReplace,
    'peerDeadTimeout': '${int.tryParse(peerDeadTimeoutSec.trim()) ?? 90}s',
    'peerCheckInterval': '${int.tryParse(peerCheckIntervalSec.trim()) ?? 30}s',
    'theme': theme,
    'closeToTray': closeToTray,
    'minimizeToTray': minimizeToTray,
    'updateCheck': updateCheck,
    if (updateNotified.isNotEmpty) 'updateNotified': updateNotified,
    'countrySlug': countrySlug,
    'loggingDisabled': loggingDisabled,
    'services': [for (final service in services) service.toJson()],
  };
}

/// The host of a peer URI, used to treat two transports of one server as the
/// same node.
String uriHost(String uri) {
  final parsed = Uri.tryParse(uri);
  if (parsed == null || parsed.host.isEmpty) return uri;
  return parsed.host.toLowerCase();
}

/// The scheme and host of a peer URI, without the query.
String shortUri(String uri) {
  final parsed = Uri.tryParse(uri);
  if (parsed == null) return uri;
  final host = parsed.hasPort ? '${parsed.host}:${parsed.port}' : parsed.host;
  return '${parsed.scheme}://$host';
}

List<String> splitList(String value) => [
  for (final item in value.split(RegExp(r'[,;\s]+')))
    if (item.trim().isNotEmpty) item.trim(),
];

/// The core stores durations as Go strings ("90s", "2m"). The window edits
/// seconds, so a duration is turned into its second count.
String _secondsOf(Object? value, int fallback) {
  if (value is num) return '${value.toInt()}';
  final text = '$value'.trim();
  if (text.isEmpty) return '$fallback';
  final match = RegExp(r'^(\d+)(ms|s|m|h)?$').firstMatch(text);
  if (match == null) return '$fallback';
  final amount = int.tryParse(match.group(1)!) ?? fallback;
  return switch (match.group(2)) {
    'ms' => '${(amount / 1000).round()}',
    'm' => '${amount * 60}',
    'h' => '${amount * 3600}',
    _ => '$amount',
  };
}

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

/// A speed limit in the unit a person reads: `500 kbps`, `20 Mbps`,
/// `1.5 Gbps`. The exit configures the limit in kbps, and `20000 kbps` is the
/// same number written in a unit nobody uses for a link.
String formatBitRate(int kbps) {
  if (kbps <= 0) return '0 kbps';
  if (kbps >= 1000000) return '${_trimRate(kbps / 1000000)} Gbps';
  if (kbps >= 1000) return '${_trimRate(kbps / 1000)} Mbps';
  return '$kbps kbps';
}

String _trimRate(double value) {
  final digits = value >= 100 ? 0 : (value >= 10 ? 1 : 2);
  var text = value.toStringAsFixed(digits);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'0+$'), '');
    text = text.replaceFirst(RegExp(r'\.$'), '');
  }
  return text;
}

String formatUptime(int seconds) {
  if (seconds <= 0) return '—';
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  if (minutes > 0) return '${minutes}m ${seconds % 60}s';
  return '${seconds}s';
}

/// The live state of the exit profiles, as the bridge reports it. The Exit page
/// shows the active profile from here: state, latency, quota, DNS, IPv6 and UDP.
class ExitStatus {
  const ExitStatus({
    this.enabled = false,
    this.state = 'off',
    this.activeId = '',
    this.profiles = const [],
    this.udp = const ExitUdpStatus(),
  });

  final bool enabled;
  final String state;
  final String activeId;
  final List<ExitProfileStatus> profiles;
  final ExitUdpStatus udp;

  ExitProfileStatus? get active {
    for (final profile in profiles) {
      if (profile.id == activeId) return profile;
    }
    return profiles.isEmpty ? null : profiles.first;
  }

  factory ExitStatus.fromJson(Map<String, dynamic> json) => ExitStatus(
    enabled: json['enabled'] as bool? ?? false,
    state: json['state'] as String? ?? 'off',
    activeId: json['activeId'] as String? ?? '',
    profiles: [
      for (final item in (json['profiles'] as List? ?? const []))
        ExitProfileStatus.fromJson(item as Map<String, dynamic>),
    ],
    udp: json['udp'] is Map<String, dynamic>
        ? ExitUdpStatus.fromJson(json['udp'] as Map<String, dynamic>)
        : const ExitUdpStatus(),
  );
}

class ExitProfileStatus {
  const ExitProfileStatus({
    required this.id,
    this.name = '',
    this.state = 'unknown',
    this.latencyMs = 0,
    this.error = '',
    this.authenticated = false,
    this.connections = 0,
    this.maxConnections = 0,
    this.udpAssociations = 0,
    this.maxUdpAssociations = 0,
    this.suspended = false,
    this.ipv6State = '',
    this.dnsAddress = '',
    this.dnsPort = 0,
    this.quota,
  });

  final String id;
  final String name;
  final String state;
  final double latencyMs;
  final String error;
  final bool authenticated;
  final int connections;
  final int maxConnections;
  final int udpAssociations;
  final int maxUdpAssociations;
  final bool suspended;
  final String ipv6State;
  final String dnsAddress;
  final int dnsPort;
  final ExitQuota? quota;

  factory ExitProfileStatus.fromJson(Map<String, dynamic> json) =>
      ExitProfileStatus(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        state: json['state'] as String? ?? 'unknown',
        latencyMs: (json['latencyMs'] as num?)?.toDouble() ?? 0,
        error: json['error'] as String? ?? '',
        authenticated: json['authenticated'] as bool? ?? false,
        connections: (json['connections'] as num?)?.toInt() ?? 0,
        maxConnections: (json['maxConns'] as num?)?.toInt() ?? 0,
        udpAssociations: (json['udpAssociations'] as num?)?.toInt() ?? 0,
        maxUdpAssociations: (json['maxUdpAssociations'] as num?)?.toInt() ?? 0,
        suspended: json['suspended'] as bool? ?? false,
        ipv6State: json['ipv6State'] as String? ?? '',
        dnsAddress: json['dnsAddress'] as String? ?? '',
        dnsPort: (json['dnsPort'] as num?)?.toInt() ?? 0,
        quota: json['quota'] is Map<String, dynamic>
            ? ExitQuota.fromJson(json['quota'] as Map<String, dynamic>)
            : null,
      );
}

class ExitQuota {
  const ExitQuota({
    this.monthlyBytes = 0,
    this.dailyBytes = 0,
    this.downKbps = 0,
    this.upKbps = 0,
    this.dayUsed = 0,
    this.monthUsed = 0,
    this.exhausted = false,
    this.reason = '',
  });

  final int monthlyBytes;
  final int dailyBytes;
  final int downKbps;
  final int upKbps;
  final int dayUsed;
  final int monthUsed;
  final bool exhausted;
  final String reason;

  bool get hasLimit => monthlyBytes > 0 || dailyBytes > 0;
  bool get hasSpeed => downKbps > 0 || upKbps > 0;

  factory ExitQuota.fromJson(Map<String, dynamic> json) => ExitQuota(
    monthlyBytes: (json['monthlyBytes'] as num?)?.toInt() ?? 0,
    dailyBytes: (json['dailyBytes'] as num?)?.toInt() ?? 0,
    downKbps: (json['downKbps'] as num?)?.toInt() ?? 0,
    upKbps: (json['upKbps'] as num?)?.toInt() ?? 0,
    dayUsed: (json['dayUsed'] as num?)?.toInt() ?? 0,
    monthUsed: (json['monthUsed'] as num?)?.toInt() ?? 0,
    exhausted: json['exhausted'] as bool? ?? false,
    reason: json['reason'] as String? ?? '',
  );
}

class ExitUdpStatus {
  const ExitUdpStatus({
    this.enabled = false,
    this.state = 'off',
    this.datagramsIn = 0,
    this.datagramsOut = 0,
    this.bytesIn = 0,
    this.bytesOut = 0,
    this.error = '',
  });

  final bool enabled;
  final String state;
  final int datagramsIn;
  final int datagramsOut;
  final int bytesIn;
  final int bytesOut;
  final String error;

  factory ExitUdpStatus.fromJson(Map<String, dynamic> json) => ExitUdpStatus(
    enabled: json['enabled'] as bool? ?? false,
    state: json['state'] as String? ?? 'off',
    datagramsIn: (json['datagramsIn'] as num?)?.toInt() ?? 0,
    datagramsOut: (json['datagramsOut'] as num?)?.toInt() ?? 0,
    bytesIn: (json['bytesIn'] as num?)?.toInt() ?? 0,
    bytesOut: (json['bytesOut'] as num?)?.toInt() ?? 0,
    error: json['error'] as String? ?? '',
  );
}

/// One row of the peer catalogue or the latency test: the URI, whether the node
/// answered and how fast. The Peers page keeps them until the next run.
class ProbeResult {
  const ProbeResult({
    required this.uri,
    this.up = false,
    this.latencyMs = 0,
    this.error = '',
  });

  final String uri;
  final bool up;
  final double latencyMs;
  final String error;

  factory ProbeResult.fromJson(Map<String, dynamic> json) => ProbeResult(
    uri: json['uri'] as String? ?? '',
    up: json['up'] as bool? ?? false,
    latencyMs: (json['latencyMs'] as num?)?.toDouble() ?? 0,
    error: json['error'] as String? ?? '',
  );
}

/// The result of asking one resolver for one name.
class DnsCheck {
  const DnsCheck({
    required this.server,
    this.ok = false,
    this.ms = 0,
    this.name = '',
    this.address = '',
    this.via = '',
    this.error = '',
  });

  final String server;
  final bool ok;
  final double ms;
  final String name;
  final String address;
  final String via;
  final String error;

  factory DnsCheck.fromJson(Map<String, dynamic> json) => DnsCheck(
    server: json['server'] as String? ?? '',
    ok: json['ok'] as bool? ?? false,
    ms: (json['ms'] as num?)?.toDouble() ?? 0,
    name: json['name'] as String? ?? '',
    address: json['address'] as String? ?? '',
    via: json['via'] as String? ?? '',
    error: json['error'] as String? ?? '',
  );
}
