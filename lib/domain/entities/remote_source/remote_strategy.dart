/// 领域层：远程源加载策略（代理降级链 + 加载状态）。
///
/// 唯一真相源：iOS `vbox/Services/RemoteSourceConfigManager.swift`
///   - `proxyHosts`（三级降级链）
///   - `enum LoadState`
library;

/// 代理降级链条目。
class ProxyHost {
  const ProxyHost({required this.name, required this.host});

  /// 代理名（用于日志/诊断）。
  final String name;

  /// 代理前缀，如 `https://ghfast.top`。
  final String host;
}

/// 加载状态（对齐 iOS `LoadState`）。
enum RemoteLoadState {
  idle,
  loading,

  /// 已从远程加载。
  loadedRemote,

  /// 已从缓存加载。
  loadedCache,

  /// 失败。
  failed,
}

/// 带版本信息的加载状态。
class RemoteLoadStatus {
  const RemoteLoadStatus(this.state, {this.version, this.message});

  final RemoteLoadState state;

  /// 配置版本（loadedRemote / loadedCache 时有值）。
  final String? version;

  /// 错误消息（failed 时有值）。
  final String? message;

  const RemoteLoadStatus.idle() : this(RemoteLoadState.idle);
  const RemoteLoadStatus.loading() : this(RemoteLoadState.loading);
  const RemoteLoadStatus.loadedRemote(String v)
      : this(RemoteLoadState.loadedRemote, version: v);
  const RemoteLoadStatus.loadedCache(String v)
      : this(RemoteLoadState.loadedCache, version: v);
  const RemoteLoadStatus.failed(String msg)
      : this(RemoteLoadState.failed, message: msg);

  /// 显示文本（对齐 iOS `displayText`）。
  String get displayText => switch (state) {
        RemoteLoadState.idle => '未同步',
        RemoteLoadState.loading => '同步中',
        RemoteLoadState.loadedRemote => '远程配置 ${version ?? ''}',
        RemoteLoadState.loadedCache => '缓存配置 ${version ?? ''}',
        RemoteLoadState.failed => '失败：${message ?? ''}',
      };

  /// 是否加载成功（远程或缓存）。
  bool get isLoaded =>
      state == RemoteLoadState.loadedRemote ||
      state == RemoteLoadState.loadedCache;
}

/// 远程源加载策略（代理降级链）。
class RemoteSourceStrategy {
  RemoteSourceStrategy._();

  /// 内置默认 manifest 地址（契约 iOS 源码同值）。
  static const String defaultManifestUrl =
      'https://vbox-ai.github.io/api/sources/manifest.json';

  /// 代理降级链：主代理 → 备用代理 → 直连（对齐 iOS `proxyHosts`）。
  ///
  /// B-02：以构造/参数注入实现「可配置常量」——调用方（如
  /// `RemoteSourceConfigManager`）可按环境覆盖；缺省对齐 iOS。
  static const List<ProxyHost> proxyHosts = <ProxyHost>[
    ProxyHost(name: 'ghfast', host: 'https://ghfast.top'),
    ProxyHost(name: 'gh-proxy', host: 'https://gh-proxy.com'),
  ];

  /// 是否为 GitHub 域名（对齐 iOS `isGitHubDomain`）：
  /// 仅 GitHub 系域名走代理链，其余直连。
  static bool isGithubHost(String host) =>
      host == 'raw.githubusercontent.com' ||
      host.endsWith('.github.io') ||
      host == 'github.com';

  /// 为原始 URL 生成候选地址列表（降级顺序）。
  ///
  /// 顺序：主代理 → 备用代理 → 直连；**仅 GitHub 域名**套代理
  /// （对齐 iOS `buildProxyURLs` 的 `isGitHubDomain` 门控），
  /// 非 GitHub URL 直接返回 `[rawUrl]`（直连）。
  static List<String> candidates(
    String rawUrl, {
    List<ProxyHost> proxies = proxyHosts,
  }) {
    final Uri? uri = Uri.tryParse(rawUrl);
    if (uri == null || !isGithubHost(uri.host)) return <String>[rawUrl];
    final List<String> out = <String>[];
    for (final ProxyHost p in proxies) {
      out.add('${p.host}/$rawUrl');
    }
    out.add(rawUrl);
    return out;
  }

  /// 缓存是否过期（基于 ttlSeconds）。
  static bool isCacheExpired({
    required int lastSyncEpochSeconds,
    required int ttlSeconds,
    required int nowEpochSeconds,
  }) {
    if (lastSyncEpochSeconds <= 0) return true;
    return (nowEpochSeconds - lastSyncEpochSeconds) >= ttlSeconds;
  }

  /// 是否需要同步（对齐 iOS `syncIfNeeded` 的判定语义）。
  ///
  /// 需同步当满足任一：
  /// - force == true
  /// - 从未同步（lastConfigVersion 为空）
  /// - 缓存过期
  /// - App 版本变化
  static bool shouldSync({
    required bool force,
    required String lastConfigVersion,
    required int lastSyncEpochSeconds,
    required int ttlSeconds,
    required int nowEpochSeconds,
    required bool appVersionChanged,
  }) {
    if (force) return true;
    if (lastConfigVersion.isEmpty) return true;
    if (appVersionChanged) return true;
    return isCacheExpired(
      lastSyncEpochSeconds: lastSyncEpochSeconds,
      ttlSeconds: ttlSeconds,
      nowEpochSeconds: nowEpochSeconds,
    );
  }
}
