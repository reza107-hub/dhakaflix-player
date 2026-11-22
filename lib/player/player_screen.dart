/// Full-screen player page built on media_kit's adaptive controls
/// (touch controls on Android, desktop controls with shortcuts elsewhere).
library;

import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../core/dhakaflix_client.dart';
import 'player_controller.dart';

const playbackSpeeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

class PlayerScreen extends StatefulWidget {
  const PlayerScreen({super.key, required this.controller, required this.entry, this.siblings = const []});

  final PlayerController controller;
  final Entry entry;
  final List<Entry> siblings;

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> with WidgetsBindingObserver {
  late final VideoController _video = VideoController(widget.controller.player);
  late final AppLifecycleListener _exitListener;
  BuildContext? _controlsContext; // A context inside the controls, for fullscreen calls.
  double _volumeBeforeMute = 100;

  PlayerController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Desktop window close: save before the process exits.
    _exitListener = AppLifecycleListener(
      onExitRequested: () async {
        await c.saveNow();
        return AppExitResponse.exit;
      },
    );
    c.addListener(_changed);
    c.open(widget.entry, siblings: widget.siblings).catchError((Object e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) c.saveNow(); // Background, lock, exit.
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _exitListener.dispose();
    c.removeListener(_changed);
    c.close();
    super.dispose();
  }

  // ---- Keyboard (desktop) ----

  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    final p = c.player;
    void fs(Future<void> Function(BuildContext) f) {
      final ctx = _controlsContext;
      if (ctx != null && ctx.mounted) f(ctx);
    }

    return {
      const SingleActivator(LogicalKeyboardKey.space): p.playOrPause,
      const SingleActivator(LogicalKeyboardKey.mediaPlayPause): p.playOrPause,
      const SingleActivator(LogicalKeyboardKey.arrowLeft): () => c.seekBy(-c.seekStep),
      const SingleActivator(LogicalKeyboardKey.arrowRight): () => c.seekBy(c.seekStep),
      const SingleActivator(LogicalKeyboardKey.arrowUp): () => p.setVolume((p.state.volume + 5).clamp(0, 100)),
      const SingleActivator(LogicalKeyboardKey.arrowDown): () => p.setVolume((p.state.volume - 5).clamp(0, 100)),
      const SingleActivator(LogicalKeyboardKey.keyM): _toggleMute,
      const SingleActivator(LogicalKeyboardKey.keyF): () => fs(toggleFullscreen),
      const SingleActivator(LogicalKeyboardKey.escape): () => fs(exitFullscreen),
    };
  }

  void _toggleMute() {
    final p = c.player;
    if (p.state.volume > 0) {
      _volumeBeforeMute = p.state.volume;
      p.setVolume(0);
    } else {
      p.setVolume(_volumeBeforeMute > 0 ? _volumeBeforeMute : 100);
    }
  }

  // ---- Menus ----

  Future<void> _openMenu(BuildContext ctx) => showModalBottomSheet<void>(
    context: ctx,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => _PlayerMenu(controller: c),
  );

  Widget _grab() => Builder(
    builder: (ctx) {
      _controlsContext = ctx;
      return const SizedBox.shrink();
    },
  );

  Widget _menuButton() => Builder(
    builder: (ctx) => IconButton(
      tooltip: 'Audio, subtitles, speed',
      icon: const Icon(Icons.tune, color: Colors.white),
      onPressed: () => _openMenu(ctx),
    ),
  );

  Widget _backButton() => IconButton(
    tooltip: 'Back',
    icon: const Icon(Icons.arrow_back, color: Colors.white),
    onPressed: () async {
      final ctx = _controlsContext;
      if (ctx != null && ctx.mounted && isFullscreen(ctx)) await exitFullscreen(ctx);
      if (mounted) Navigator.of(context).maybePop();
    },
  );

  Widget _title() => Expanded(
    child: Text(
      widget.entry.name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.white, fontSize: 15),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final step = c.seekStep;
    final top = [_backButton(), _title(), _grab()];
    // Keep controls clear of the status/navigation bars outside fullscreen.
    MaterialVideoControlsThemeData mobileTheme(EdgeInsets padding) => MaterialVideoControlsThemeData(
      padding: padding,
      seekOnDoubleTap: true,
      seekOnDoubleTapForwardDuration: step,
      seekOnDoubleTapBackwardDuration: step,
      volumeGesture: true,
      brightnessGesture: true,
      seekBarThumbSize: 14,
      seekBarHeight: 3,
      buttonBarButtonSize: 28,
      topButtonBar: top,
      bottomButtonBar: [
        const MaterialPositionIndicator(),
        const Spacer(),
        _menuButton(),
        const MaterialFullscreenButton(),
      ],
    );
    final mobile = mobileTheme(MediaQuery.paddingOf(context));
    final mobileFullscreen = mobileTheme(EdgeInsets.zero);
    final desktop = MaterialDesktopVideoControlsThemeData(
      keyboardShortcuts: _shortcuts,
      toggleFullscreenOnDoublePress: true,
      topButtonBar: top,
      bottomButtonBar: [
        const MaterialDesktopSkipPreviousButton(),
        const MaterialDesktopPlayOrPauseButton(),
        const MaterialDesktopVolumeButton(),
        const MaterialDesktopPositionIndicator(),
        const Spacer(),
        _menuButton(),
        const MaterialDesktopFullscreenButton(),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.black,
      body: MaterialVideoControlsTheme(
        normal: mobile,
        fullscreen: mobileFullscreen,
        child: MaterialDesktopVideoControlsTheme(
          normal: desktop,
          fullscreen: desktop,
          child: Stack(
            fit: StackFit.expand,
            children: [
              Video(
                controller: _video,
                controls: Platform.isAndroid ? MaterialVideoControls : MaterialDesktopVideoControls,
              ),
              if (c.reconnecting != null) _Banner(text: c.reconnecting!, spinner: true),
              if (c.fatalError != null) _Banner(text: c.fatalError!, spinner: false),
            ],
          ),
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.spinner});
  final String text;
  final bool spinner;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topCenter,
    child: Padding(
      padding: const EdgeInsets.only(top: 64),
      child: Material(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (spinner) ...[
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 12),
              ],
              Flexible(
                child: Text(text, style: const TextStyle(color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// Bottom sheet: audio, subtitles (size and delay), speed.
class _PlayerMenu extends StatelessWidget {
  const _PlayerMenu({required this.controller});
  final PlayerController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      final c = controller;
      final audio = c.audioTracks;
      final currentAudio = c.player.state.track.audio.id;
      final subs = c.subtitleOptions;
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _Heading('Audio'),
              if (audio.isEmpty) const Text('No audio tracks'),
              for (final t in audio)
                _Choice(
                  label: trackLabel(t.language, t.title, t.id),
                  detail: [
                    t.codec,
                    if (t.channelscount != null) '${t.channelscount}ch',
                  ].whereType<String>().join(' · '),
                  selected: t.id == currentAudio,
                  onTap: () => c.selectAudio(t),
                ),
              const _Heading('Subtitles'),
              for (final o in subs)
                _Choice(label: o.label, selected: o.key == c.subtitleKey, onTap: () => c.selectSubtitle(o)),
              if (c.subtitleKey != SubtitleOption.off.key) ...[
                _Stepper(
                  label: 'Size',
                  value: '${(c.subtitleScale * 100).round()}%',
                  onMinus: () => c.setSubtitleScale(c.subtitleScale - 0.1),
                  onPlus: () => c.setSubtitleScale(c.subtitleScale + 0.1),
                ),
                _Stepper(
                  label: 'Delay',
                  value: '${c.subtitleDelay >= 0 ? '+' : ''}${c.subtitleDelay.toStringAsFixed(1)} s',
                  onMinus: () => c.setSubtitleDelay(c.subtitleDelay - 0.1),
                  onPlus: () => c.setSubtitleDelay(c.subtitleDelay + 0.1),
                ),
              ],
              const _Heading('Speed'),
              Wrap(
                spacing: 8,
                children: [
                  for (final s in playbackSpeeds)
                    ChoiceChip(
                      label: Text('${s}x'),
                      selected: c.player.state.rate == s,
                      onSelected: (_) => c.setSpeed(s),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall),
  );
}

class _Choice extends StatelessWidget {
  const _Choice({required this.label, required this.selected, required this.onTap, this.detail});
  final String label;
  final String? detail;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off),
    title: Text(label, maxLines: 2, overflow: TextOverflow.ellipsis),
    subtitle: (detail == null || detail!.isEmpty) ? null : Text(detail!),
    onTap: onTap,
  );
}

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.value, required this.onMinus, required this.onPlus});
  final String label, value;
  final VoidCallback onMinus, onPlus;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(width: 64, child: Text(label)),
      IconButton(onPressed: onMinus, icon: const Icon(Icons.remove)),
      SizedBox(width: 72, child: Text(value, textAlign: TextAlign.center)),
      IconButton(onPressed: onPlus, icon: const Icon(Icons.add)),
    ],
  );
}
