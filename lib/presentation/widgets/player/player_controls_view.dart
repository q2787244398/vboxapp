/// 表现层：播放器控制层主视图（批次 C · C-02 / C-04）。
///
/// 组装 [PlayerTopBar] ＋ 中央播放/暂停覆盖层 ＋ [PlayerProgressBar] ＋
/// [PlayerBottomBar] ＋ 各类面板（选集 / 清晰度 / 倍速 / 内核 / 弹幕设置）。
/// 面板摆放随形态：竖屏底部抽屉、横屏右侧滑出。
///
/// 纯受控：全部状态与动作来自 [PlayerControlsController]；视频画面由调用方
/// 经 [videoBuilder] 注入（控制层不关心具体渲染后端）。
library;

import 'package:flutter/material.dart';

import '../../../platform/player/danmaku/danmaku_settings.dart';
import '../../theme/tokens/colors.dart';
import '../../theme/tokens/spacing.dart';
import '../../ui_mode/ui_mode.dart';
import 'danmaku/danmaku_settings_panel.dart';
import 'panels/player_panels.dart';
import 'player_bottom_bar.dart';
import 'player_controls_controller.dart';
import 'player_progress_bar.dart';
import 'player_top_bar.dart';

/// 播放器控制层主视图。
class PlayerControlsView extends StatelessWidget {
  /// 构造。
  const PlayerControlsView({
    super.key,
    required this.controller,
    this.videoBuilder,
    this.danmakuSettings,
    this.onDanmakuSettingsChanged,
    this.showLock = false,
  });

  /// 控制层视图状态。
  final PlayerControlsController controller;

  /// 视频画面构建器（调用方注入实际渲染视图；null 显示深色占位）。
  final WidgetBuilder? videoBuilder;

  /// 当前弹幕设置（弹幕设置面板用；null 时隐藏该面板内容）。
  final DanmakuSettings? danmakuSettings;

  /// 弹幕设置变更回调。
  final ValueChanged<DanmakuSettings>? onDanmakuSettingsChanged;

  /// 是否显示顶栏锁定按钮。
  final bool showLock;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (BuildContext context, Widget? _) {
        final UiForm form = controller.form;
        final bool landscape = form.isLandscape;
        return ColoredBox(
          color: VboxColors.playerBackground,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // 视频画面（或占位）
              videoBuilder?.call(context) ??
                  const ColoredBox(color: VboxColors.playerBackground),
              // 中央播放覆盖层
              if (!controller.isPlaying) _CenterPlayOverlay(controller),
              // 顶栏
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: PlayerTopBar(
                  form: form,
                  title: controller.title,
                  subtitle: controller.subtitle,
                  showLock: showLock,
                  locked: false,
                  onBack: controller.onBack,
                  onCast: controller.onCast,
                  onToolsMenu: controller.onToggleToolsMenu,
                ),
              ),
              // 底部控制区（进度条 + 底栏）
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _BottomControls(controller: controller),
              ),
              // 面板层
              _PanelHost(
                controller: controller,
                landscape: landscape,
                danmakuSettings: danmakuSettings,
                onDanmakuSettingsChanged: onDanmakuSettingsChanged,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 中央播放/暂停覆盖层。
class _CenterPlayOverlay extends StatelessWidget {
  const _CenterPlayOverlay(this.controller);

  final PlayerControlsController controller;

  @override
  Widget build(BuildContext context) {
    final bool enabled = controller.onTogglePlay != null;
    return Center(
      child: Material(
        color: Colors.black38,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? controller.togglePlay : null,
          child: Padding(
            padding: const EdgeInsets.all(VboxSpacing.xl),
            child: Icon(
              controller.isPlaying
                  ? Icons.pause_rounded
                  : Icons.play_arrow_rounded,
              size: 40,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

/// 底部控制区（进度条 + 底栏，随形态留白）。
class _BottomControls extends StatelessWidget {
  const _BottomControls({required this.controller});

  final PlayerControlsController controller;

  @override
  Widget build(BuildContext context) {
    final bool landscape = controller.form.isLandscape;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            Colors.transparent,
            Colors.black.withValues(alpha: landscape ? 0.55 : 0.70),
          ],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          PlayerProgressBar(
            positionMs: controller.positionMs,
            durationMs: controller.durationMs,
            bufferedMs: controller.bufferedMs,
            isLive: controller.isLive,
            onSeek: controller.onSeek,
          ),
          PlayerBottomBar(controller: controller),
        ],
      ),
    );
  }
}

/// 面板宿主：按形态摆放当前打开的面板（竖屏底部抽屉 / 横屏右侧滑出）。
class _PanelHost extends StatelessWidget {
  const _PanelHost({
    required this.controller,
    required this.landscape,
    this.danmakuSettings,
    this.onDanmakuSettingsChanged,
  });

  final PlayerControlsController controller;
  final bool landscape;
  final DanmakuSettings? danmakuSettings;
  final ValueChanged<DanmakuSettings>? onDanmakuSettingsChanged;

  @override
  Widget build(BuildContext context) {
    final Widget? panel = _currentPanel();
    if (panel == null) return const SizedBox.shrink();
    final double? width = landscape ? 380.0 : null;
    return Positioned(
      left: landscape ? null : 0,
      right: 0,
      bottom: 0,
      top: landscape ? 0 : null,
      width: width,
      child: SafeArea(
        top: landscape,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          child: panel,
        ),
      ),
    );
  }

  Widget? _currentPanel() {
    final void Function() close = controller.closeAllPanels;
    if (controller.showEpisodePicker) {
      return EpisodePickerPanelShell(
        key: const ValueKey<String>('episode'),
        episodes: controller.episodes,
        currentIndex: controller.currentEpisodeIndex,
        onSelect: controller.onSelectEpisode == null
            ? null
            : (int i) => controller.selectEpisode(i),
        onClose: close,
      );
    }
    if (controller.showQualityPicker) {
      return QualityPickerPanel(
        key: const ValueKey<String>('quality'),
        qualities: controller.qualities,
        selectedIndex: controller.selectedQuality,
        onSelect: controller.onSelectQuality == null
            ? null
            : (int i) => controller.selectQuality(i),
        onClose: close,
      );
    }
    if (controller.showSpeedPicker) {
      return SpeedPickerPanel(
        key: const ValueKey<String>('speed'),
        current: controller.speed,
        onSelect: controller.onSelectSpeed == null
            ? null
            : (double s) => controller.selectSpeed(s),
        onClose: close,
      );
    }
    if (controller.showEnginePicker) {
      return EnginePickerPanel(
        key: const ValueKey<String>('engine'),
        backends: controller.backends,
        current: controller.currentBackend,
        onSelect: controller.onSelectBackend == null
            ? null
            : (b) => controller.selectBackend(b),
        onClose: close,
      );
    }
    if (controller.showDanmakuSettings) {
      final DanmakuSettings? s = danmakuSettings;
      if (s == null) return null;
      return PlayerPanelContainer(
        key: const ValueKey<String>('danmaku'),
        title: '弹幕设置',
        onClose: close,
        child: DanmakuSettingsPanelBody(
          settings: s,
          onChanged: onDanmakuSettingsChanged ?? (_) {},
        ),
      );
    }
    if (controller.showToolsMenu) {
      return PlayerPanelContainer(
        key: const ValueKey<String>('tools'),
        title: '更多',
        onClose: close,
        child: const Text(
          '投屏 / 播放设置（后续批次接入）',
          style: TextStyle(fontSize: 14, color: Colors.white60),
        ),
      );
    }
    return null;
  }
}

/// 弹幕设置面板主体（复用 [DanmakuSettingsPanel] 结构但去壳，供面板宿主嵌入）。
class DanmakuSettingsPanelBody extends StatelessWidget {
  /// 构造。
  const DanmakuSettingsPanelBody({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  /// 当前设置。
  final DanmakuSettings settings;

  /// 变更回调。
  final ValueChanged<DanmakuSettings> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SwitchListTile(
          dense: true,
          title: const Text(
            '弹幕开关',
            style: TextStyle(fontSize: 14, color: Colors.white),
          ),
          value: settings.enabled,
          activeThumbColor: Colors.white,
          onChanged: (bool v) => onChanged(settings.copyWith(enabled: v)),
        ),
        if (settings.enabled) ..._sliders(),
      ],
    );
  }

  List<Widget> _sliders() => <Widget>[
        _slider(
          label: '不透明度 ${(settings.opacity * 100).round()}%',
          value: settings.opacity,
          min: 0.1,
          max: 1.0,
          divisions: 9,
          onChanged: (double v) => onChanged(settings.copyWith(opacity: v)),
        ),
        _slider(
          label: '字号 ${settings.fontSize.round()}px',
          value: settings.fontSize,
          min: 10,
          max: 32,
          divisions: 22,
          onChanged: (double v) => onChanged(settings.copyWith(fontSize: v)),
        ),
        _slider(
          label: '显示区域 ${(settings.area * 100).round()}%',
          value: settings.area,
          min: 0.25,
          max: 1.0,
          divisions: 7,
          onChanged: (double v) => onChanged(settings.copyWith(area: v)),
        ),
      ];

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) =>
      ListTile(
        dense: true,
        title: Text(
          label,
          style: const TextStyle(fontSize: 13, color: Colors.white70),
        ),
        subtitle: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      );
}
