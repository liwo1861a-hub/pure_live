import 'dart:async';
import 'dart:developer';

import 'package:flutter/scheduler.dart';
import 'package:pure_live/core/index.dart';
import 'package:pure_live/core/platform/platform_utils.dart';
import 'package:pure_live/domains/live/domain/live_player_facade.dart';
import 'package:pure_live/core/player/kernel/floating_handle_keeper.dart';
import 'package:pure_live/core/player/kernel/player_kernel_service.dart';
import 'package:pure_live/core/player/core/background_playback_service.dart';
import 'package:pure_live/core/player/presentation/fullscreen_window.dart' show WindowService;
import 'package:pure_live/domains/live/presentation/playback/controllers/live_play_controller.dart';
import 'package:pure_live/domains/live/presentation/playback/widgets/layout/live_play_video.dart' show shouldFloatAfterLivePlayExit;
import 'package:pure_live/domains/live/domain/global_player_service.dart';

class LiveRouteObserver extends RouteObserver<PageRoute<dynamic>> {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    switch (route.settings.name) {
      case RoutePath.kLivePlay:
        _onLivePlayEnter();
        break;
      case RoutePath.kMultiview:
        _onMultiviewEnter();
      case RoutePath.kLocalVideoPlayer:
        _onLocalVideoPlayerEnter();
      case RoutePath.kRecordPage:
        _setVideoLayerVisible(false);
        break;
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    switch (route.settings.name) {
      case RoutePath.kLivePlay:
        _onLivePlayExit(route);
        break;
      case RoutePath.kRecordPage:
        _restoreVideoLayerAfterRouteExit(route);
        break;
    }
  }

  void _onLivePlayEnter() {
    final playerManager = GlobalPlayerService.instance.player;
    playerManager.setVideoPresentationVisible(true);
    unawaited(playerManager.closeAppFloating());
    // 关键门禁：只有进入直播间观看直播时，才允许切桌面进入系统小窗！
    unawaited(BackgroundPlaybackService.setPipAutoEnter(true));
    // A recording handed to the small window is taken back: two videos cannot
    // share the surface (or the audio). Reclaiming also closes the window
    // itself, not just the player behind it.
    unawaited(FloatingHandleKeeper.reclaimCurrent(PlayerKernelService.instance.kernel));
  }

  /// Watching a recording on its own page.
  ///
  /// The live small window would otherwise keep playing over it while both hold
  /// audio, and a recording that was floating is taken back by the page that
  /// owns it — the window included, so the new page is not covered by a window
  /// whose player was just disposed.
  void _onLocalVideoPlayerEnter() {
    unawaited(BackgroundPlaybackService.setPipAutoEnter(false));
    unawaited(GlobalPlayerService.instance.player.closeAppFloating());
    unawaited(FloatingHandleKeeper.reclaimCurrent(PlayerKernelService.instance.kernel));
  }

  void _onMultiviewEnter() {
    unawaited(BackgroundPlaybackService.setPipAutoEnter(false));
    final playerManager = GlobalPlayerService.instance.player;
    unawaited(playerManager.closeAppFloating());
    unawaited(playerManager.close());
    final controller = _findLivePlayController();
    if (controller == null) return;
    final state = controller.state.value;
    state.player.videoController?.clearListener();
  }

  void _onLivePlayExit(Route<dynamic> route) {
    // 关键门禁：退出直播间时，立即关闭切桌面进入系统小窗权限，防止在主页、分类、设置等页面误触发小窗！
    unawaited(BackgroundPlaybackService.setPipAutoEnter(false));
    final controller = _findLivePlayController();
    if (controller == null) return;

    final state = controller.state.value;
    final preventFloating = controller.takeSuppressAppFloatingOnNextPop();

    controller.updateRoom(success: false);

    final playerManager = GlobalPlayerService.instance.player;
    // 关键修复：只要房间处于开播状态、播放器正在播放或有视频，退出直播间时一律允许自动开启小窗播放！
    final canFloat = (state.room.isLiving || playerManager.isPlayingNow || state.player.videoController != null) && state.room.loadError == null;
    if (canFloat && _shouldShowFloating(preventFloating)) {
      _showFloatingAfterExit(route: route, controller: controller, playerManager: playerManager);
    } else {
      state.player.videoController?.clearListener();
      unawaited(playerManager.close());
    }

    if (PlatformUtils.isMobile) {
      WindowService().doExitFullScreen();
    }
  }

  void _setVideoLayerVisible(bool visible) {
    final controller = _findLivePlayController();
    if (controller == null) return;
    // Windows removes the Texture subtree while this opaque route is visible.
    // Stop presentation-only stall supervision before that intentional
    // teardown so a long stay in recorder centre does not reopen a healthy
    // Huya transport in the background.
    GlobalPlayerService.instance.player.setVideoPresentationVisible(visible);
  }

  /// A popped route remains in the overlay during its reverse transition.
  /// Reattaching media_kit's Windows texture in didPop used to overlap that
  /// transition and produced a reproducible flutter_windows.dll access
  /// violation when returning from the recorder centre.  Wait for the route
  /// to be fully removed, then cross one more frame boundary before restoring
  /// the live surface.
  void _restoreVideoLayerAfterRouteExit(Route<dynamic> route) {
    unawaited(
      _waitForRouteExit(route).then((_) async {
        await SchedulerBinding.instance.endOfFrame;
        final controller = _findLivePlayController();
        if (controller != null && !controller.isClosed) {
          // Let the rebuilt Texture publish its viewport before presentation
          // supervision resumes. The first mounted layout force-reasserts the
          // Windows native size even when it equals the previous viewport.
          await SchedulerBinding.instance.endOfFrame;
          GlobalPlayerService.instance.player.setVideoPresentationVisible(true);
        }
      }),
    );
  }

  bool _shouldShowFloating(bool preventFloating) {
    return SettingsService.to.player.floatPlay.v && !preventFloating;
  }

  void _showFloatingAfterExit({
    required Route<dynamic> route,
    required LivePlayController controller,
    required LivePlayerFacade playerManager,
  }) {
    final routeExitCompleted = _waitForRouteExit(route);
    controller.prepareAppFloating(routeUnmounted: routeExitCompleted);
    // 立即通过下一帧调度展示应用内悬浮小窗，杜绝转场动画阻塞导致小窗漏出
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final current = Get.currentRoute;
      if (current == RoutePath.kLivePlay || current == RoutePath.kMultiview) return;
      if (current == RoutePath.kLocalVideoPlayer) return;
      playerManager.showAppFloating();
    });
    unawaited(
      routeExitCompleted.then((_) {
        // Race guard: opening another live room or the multiview grid right
        // after leaving this one closes the floating window synchronously in
        // their enter hooks — but this delayed callback then runs afterwards
        // and pops the window back up over the new page. If we are already
        // back in a player surface, the user moved on; stay closed.
        final current = Get.currentRoute;
        if (current == RoutePath.kLivePlay || current == RoutePath.kMultiview) return;
        // The recording player is the same statement for the other player: a
        // room that returned to the small window after the viewer already
        // opened a recording would run its audio over the recording's.
        if (current == RoutePath.kLocalVideoPlayer) return;

        // The small window's danmaku is the facade's business: it resolves the
        // controller that still owns playback when the overlay builds, while a
        // controller read here is gone as soon as the room's route is disposed.
        playerManager.showAppFloating();
      }),
    );
  }

  Future<void> _waitForRouteExit(Route<dynamic> route) {
    if (route is TransitionRoute<dynamic>) {
      return route.completed;
    }
    return SchedulerBinding.instance.endOfFrame;
  }

  LivePlayController? _findLivePlayController() {
    try {
      if (!Get.isRegistered<LivePlayController>()) return null;
      return Get.find<LivePlayController>();
    } catch (e, stackTrace) {
      log('Failed to find LivePlayController', error: e, stackTrace: stackTrace);
      return null;
    }
  }
}

