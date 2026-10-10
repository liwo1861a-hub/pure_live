import 'dart:async';

import 'package:pure_live/gen/env.g.dart';
import 'package:pure_live/common/index.dart';
import 'package:pure_live/plugins/race_http.dart';
import 'package:pure_live/common/consts/app_consts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pure_live/common/utils/githup_mirror.dart';
import 'package:pure_live/common/global/platform_utils.dart';

class VersionUtil {
  static PackageInfo? _packageInfo;

  /// Release/update repository for this maintained distribution.
  ///
  /// Keeping the owner configurable lets downstream builders select their own
  /// release feed without editing runtime code. Defaults to the maintained release feed.
  static String get updateOwner => AppConfig.pureliveUpdateOwner;
  static String get updateRepository => AppConfig.pureliveUpdateRepository;
  static String get projectUrl => 'https://github.com/$updateOwner/$updateRepository';
  static String get issuesUrl => '$projectUrl/issues';
  static String get githubUrl => 'https://github.com/$updateOwner';

  static const String email = 'luzi1861a@gmail.com';
  static const String emailUrl = 'mailto:luzi1861a@gmail.com?subject=PureLive Feedback';

  static const String telegramGroup = 't.me/lzvideo_channel';
  static const String telegramGroupUrl = 'https://t.me/lzvideo_channel';

  static String get releaseUrl => 'https://gh.lz1861.ccwu.cc/https://api.github.com/repos/$updateOwner/$updateRepository/releases?per_page=30';

  static GitHubMirror get mirror => GitHubMirror(owner: updateOwner, repo: updateRepository, branch: 'master');

  static List<String> get _versionUrls => [
    'https://gh.lz1861.ccwu.cc/api/version',
    mirror.rawUrl('assets/version.json'),
    mirror.officialRawUrl('assets/version.json'),
  ];

  final isHasNewVersion = false.obs;

  static String latestVersion = '';
  static int? latestBuildNumber;
  static int latestVersionNum = 0;
  static String latestUpdateLog = '';
  static bool prerelease = false;
  static String downloadUrl = '';
  static Set<String> latestAndroidAbis = AppConsts.supportAndroidAbis;
  static bool latestWindowsMsixAvailable = false;
  var allReleased = [].obs;

  static Map<String, dynamic>? _cachedVersionJson;

  static final RxBool historyLoading = false.obs;
  static final RxBool historyError = false.obs;

  static Future<void> initPackageInfo() async {
    _packageInfo = await PackageInfo.fromPlatform();
  }

  static String get version {
    if (_packageInfo == null) return '0.0.0';
    return _packageInfo!.version;
  }

  static int get buildNumber {
    if (_packageInfo == null) return 0;
    return int.tryParse(_packageInfo!.buildNumber) ?? 0;
  }

  Future<void> checkUpdate() async {
    if (_cachedVersionJson != null) {
      _applyVersionData(_cachedVersionJson!);
      isHasNewVersion.value = hasNewVersion();
      return;
    }

    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final urls = _versionUrls.map((e) => '$e?ts=$timestamp').toList();

      final data = await RaceHttp.fetchJson(
        urls,
        headers: {
          'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (data == null) {
        latestUpdateLog = '更新检查失败';
        return;
      }

      _cachedVersionJson = data;
      _applyVersionData(data);
      isHasNewVersion.value = hasNewVersion();
      debugPrint("🏁 更新线路成功");
    } catch (e) {
      debugPrint("⚠️ 更新检查失败: $e");
      latestVersion = version;
      latestUpdateLog = '更新检查失败';
    }
  }

  static void _applyVersionData(Map<String, dynamic> data) {
    final selected = selectPlatformVersionData(data, platform: _currentPlatformKey);
    latestVersion = selected['version']?.toString() ?? version;
    latestVersionNum = selected['version_num'] ?? 0;
    latestBuildNumber = selected['build_number'];
    latestUpdateLog = selected['version_desc']?.toString() ?? '';
    prerelease = selected['prerelease'] == true;
    final rawDownloadUrl = selected['download_url']?.toString() ?? '';
    downloadUrl = GitHubMirror.speedUpUrl(rawDownloadUrl);
    latestAndroidAbis = selectAndroidAbis(selected);
    latestWindowsMsixAvailable = selected['windows_msix_available'] == true;
  }

  /// Only advertises APK variants that the release feed says were published.
  /// Older feeds default to arm64, matching this maintenance branch's local
  /// release target, rather than generating links to missing assets.
  static Set<String> selectAndroidAbis(Map<String, dynamic> data) {
    final raw = data['android_abis'];
    if (raw is! List) return const {'arm64-v8a'};
    return raw.map((item) => item.toString()).where(AppConsts.supportAndroidAbis.contains).toSet();
  }

  /// Keeps update announcements aligned with the artifacts that were really
  /// published for each platform. The top-level object remains the fallback
  /// for older feeds and older clients.
  static Map<String, dynamic> selectPlatformVersionData(Map<String, dynamic> data, {required String platform}) {
    final platforms = data['platforms'];
    final platformData = platforms is Map ? platforms[platform] : null;
    if (platformData is! Map) return data;
    return {...data, ...Map<String, dynamic>.from(platformData)};
  }

  static String get _currentPlatformKey {
    if (PlatformUtils.isWindows) return 'windows';
    if (PlatformUtils.isAndroid) return 'android';
    if (PlatformUtils.isMacOS) return 'macos';
    if (PlatformUtils.isIOS) return 'ios';
    if (PlatformUtils.isLinux) return 'linux';
    return 'default';
  }

  static bool hasNewVersion() {
    try {
      final latestClean = latestVersion.split('-')[0].replaceAll('v', '').trim();
      final currentClean = version.split('-')[0].replaceAll('v', '').trim();

      final latestParts = latestClean.split('.').map(int.parse).toList();
      final currentParts = currentClean.split('.').map(int.parse).toList();

      final maxLength = latestParts.length > currentParts.length ? latestParts.length : currentParts.length;

      while (latestParts.length < maxLength) {
        latestParts.add(0);
      }
      while (currentParts.length < maxLength) {
        currentParts.add(0);
      }

      for (int i = 0; i < maxLength; i++) {
        if (latestParts[i] > currentParts[i]) return true;
        if (latestParts[i] < currentParts[i]) return false;
      }
    } catch (_) {}
    return false;
  }
}
