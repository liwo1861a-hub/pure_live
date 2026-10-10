import 'dart:io';

import 'package:pure_live/common/index.dart';
import 'package:pure_live/common/utils/githup_mirror.dart';
import 'package:pure_live/common/widgets/download_apk_dialog.dart';

Future<bool> requestStorageInstallPermission() async {
  if (await Permission.requestInstallPackages.isDenied) {
    final status = Permission.requestInstallPackages.request();
    return status.isGranted;
  }
  return true;
}

List<String> getMirrorUrls(String apkUrl, {bool githubOriginOnly = false}) {
  if (apkUrl.trim().isEmpty) return const [];
  return [apkUrl];
}

Future<void> downloadAndInstallApk(String apkUrl, {String? fileName}) async {
  final acceleratedUrl = GitHubMirror.speedUpUrl(apkUrl);
  if (Platform.isAndroid) {
    try {
      final hasInstallPermission = await requestStorageInstallPermission();
      if (!hasInstallPermission) {
        ToastUtil.show(i18n("grant_install_permission"));
        openAppSettings();
        return;
      }
    } catch (e) {
      ToastUtil.show('${i18n("request_install_permission_failed")}${e.toString()}');
    }
  }
  ToastUtil.show(i18n("downloading_apk", args: {"version": VersionUtil.latestVersion}));
  Get.dialog(
    DownloadApkDialog(apkUrl: acceleratedUrl, version: VersionUtil.latestVersion, fileName: fileName),
    barrierDismissible: false,
  );
}
