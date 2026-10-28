import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../../app/providers.dart';
import '../../app/theme/app_tokens.dart';
import '../../core/services/call_repository.dart';
import '../../core/ui/avatar_view.dart';
import '../../core/utils/formatters.dart';
import 'call_session.dart';

class ActiveCallScreen extends ConsumerStatefulWidget {
  const ActiveCallScreen({
    super.key,
    required this.call,
    required this.peerTitle,
    required this.outgoing,
    required this.video,
    this.peerAvatarPath,
  });

  final CallRecord call;
  final String peerTitle;
  final bool outgoing;
  final bool video;
  final String? peerAvatarPath;

  @override
  ConsumerState<ActiveCallScreen> createState() => _ActiveCallScreenState();
}

class _ActiveCallScreenState extends ConsumerState<ActiveCallScreen> {
  late final CallSession _session;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    final deps = ref.read(depsProvider);
    _session = CallSession(
      client: deps.client,
      repo: deps.calls,
      realtime: deps.realtime.events,
      call: widget.call,
      outgoing: widget.outgoing,
      video: widget.video,
      peerTitle: widget.peerTitle,
    )..addListener(_onSessionChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _session.start());
  }

  void _onSessionChanged() {
    if (_closing) return;
    if (_session.isEnded) {
      _closing = true;
      final delay = _session.phase == CallPhase.failed
          ? const Duration(milliseconds: 1800)
          : const Duration(milliseconds: 700);
      Future<void>.delayed(delay, () {
        if (mounted) Navigator.of(context).maybePop();
      });
    }
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _session,
      builder: (context, _) {
        final connected = _session.phase == CallPhase.active;
        return Scaffold(
          backgroundColor: const Color(0xFF05080F),
          body: SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                _RemoteArea(
                  session: _session,
                  title: widget.peerTitle,
                  avatarPath: widget.peerAvatarPath,
                  video: widget.video,
                ),
                _Header(session: _session, title: widget.peerTitle),
                if (widget.video && !_session.cameraOff)
                  Positioned(
                    top: 84,
                    right: AppTokens.space16,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppTokens.radiusCard),
                      child: SizedBox(
                        width: 108,
                        height: 156,
                        child: RTCVideoView(
                          _session.localRenderer,
                          mirror: true,
                          objectFit:
                              RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: AppTokens.space24,
                  child: _Controls(
                    session: _session,
                    video: widget.video,
                    connected: connected,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RemoteArea extends StatelessWidget {
  const _RemoteArea({
    required this.session,
    required this.title,
    required this.video,
    this.avatarPath,
  });

  final CallSession session;
  final String title;
  final bool video;
  final String? avatarPath;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    if (video && session.remoteVideoActive) {
      return RTCVideoView(
        session.remoteRenderer,
        objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
      );
    }
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFF0B1526), Color(0xFF05080F)],
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AvatarView(name: title, path: avatarPath, size: 132),
          const SizedBox(height: AppTokens.space24),
          Text(
            title,
            style: text.titleLarge?.copyWith(color: Colors.white),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppTokens.space8),
          Text(
            session.phase == CallPhase.active
                ? Formatters.duration(session.elapsed)
                : session.statusLabel ?? 'Menghubungkan…',
            style: text.bodyMedium?.copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.session, required this.title});

  final CallSession session;
  final String title;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Padding(
        padding: const EdgeInsets.all(AppTokens.space16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.white54,
                  size: 14,
                ),
                const SizedBox(width: 4),
                Text(
                  'Terenkripsi',
                  style: text.labelSmall?.copyWith(color: Colors.white54),
                ),
              ],
            ),
            const SizedBox(height: AppTokens.space8),
            Text(
              title,
              style: text.titleMedium?.copyWith(color: Colors.white),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (session.phase == CallPhase.active)
              Text(
                Formatters.duration(session.elapsed),
                style: text.bodySmall?.copyWith(color: Colors.white70),
              )
            else if (session.statusLabel != null)
              Text(
                session.statusLabel!,
                style: text.bodySmall?.copyWith(
                  color: session.phase == CallPhase.failed
                      ? const Color(0xFFF87171)
                      : Colors.white70,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Controls extends StatelessWidget {
  const _Controls({
    required this.session,
    required this.video,
    required this.connected,
  });

  final CallSession session;
  final bool video;
  final bool connected;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _RoundButton(
          icon: session.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
          label: session.muted ? 'Bisukan' : 'Mikrofon',
          active: session.muted,
          onTap: session.toggleMute,
        ),
        if (!video)
          _RoundButton(
            icon: session.speakerOn
                ? Icons.volume_up_rounded
                : Icons.volume_down_rounded,
            label: 'Speaker',
            active: session.speakerOn,
            onTap: () => session.toggleSpeaker(),
          ),
        if (video) ...[
          _RoundButton(
            icon: session.cameraOff
                ? Icons.videocam_off_rounded
                : Icons.videocam_rounded,
            label: 'Kamera',
            active: session.cameraOff,
            onTap: session.toggleCamera,
          ),
          _RoundButton(
            icon: Icons.cameraswitch_rounded,
            label: 'Putar',
            onTap: () => session.switchCamera(),
          ),
        ],
        const SizedBox(width: AppTokens.space12),
        _RoundButton(
          icon: Icons.call_end_rounded,
          label: 'Akhiri',
          danger: true,
          onTap: () => session.hangUp(),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final background = danger
        ? const Color(0xFFDC2626)
        : active
        ? Colors.white
        : Colors.white.withValues(alpha: 0.12);
    final foreground = danger
        ? Colors.white
        : active
        ? const Color(0xFF0B1526)
        : Colors.white;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTokens.space8),
      child: Semantics(
        label: label,
        button: true,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: background,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: foreground, size: 26),
          ),
        ),
      ),
    );
  }
}
