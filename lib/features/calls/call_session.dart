import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/config/env.dart';
import '../../core/services/call_repository.dart';
import '../../core/services/realtime_service.dart';
import '../../core/utils/app_error.dart';

enum CallPhase { preparing, ringing, connecting, active, ended, failed }

/// Owns one WebRTC peer connection plus its signalling channel.
///
/// Signalling rides on the RLS-protected private topic `call:<call_id>`; the
/// durable `calls` row is the source of truth for status transitions. The
/// caller re-sends its offer until an answer arrives, because broadcasts are
/// ephemeral and the callee joins the topic only after accepting.
class CallSession extends ChangeNotifier {
  CallSession({
    required SupabaseClient client,
    required CallRepository repo,
    required Stream<RealtimeEvent> realtime,
    required this.call,
    required this.outgoing,
    required this.video,
    required this.peerTitle,
  }) : _client = client,
       _repo = repo,
       _realtime = realtime;

  final SupabaseClient _client;
  final CallRepository _repo;
  final Stream<RealtimeEvent> _realtime;

  final CallRecord call;
  final bool outgoing;
  final bool video;
  final String peerTitle;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  CallPhase _phase = CallPhase.preparing;
  String? _statusLabel;
  String? _errorMessage;
  bool _muted = false;
  bool _cameraOff = false;
  bool _speakerOn = false;
  Duration _elapsed = Duration.zero;
  bool _remoteVideoActive = false;

  RTCPeerConnection? _pc;
  MediaStream? _local;
  RealtimeChannel? _channel;
  StreamSubscription<RealtimeEvent>? _eventsSub;
  Timer? _offerTimer;
  Timer? _offerTimeout;
  Timer? _ticker;

  final List<RTCIceCandidate> _pendingCandidates = [];
  final List<Map<String, dynamic>> _pendingOutgoing = [];
  bool _subscribed = false;
  bool _remoteSet = false;
  bool _started = false;
  bool _ended = false;
  bool _disposed = false;
  DateTime? _activeAt;

  CallPhase get phase => _phase;
  String? get statusLabel => _statusLabel;
  String? get errorMessage => _errorMessage;
  bool get muted => _muted;
  bool get cameraOff => _cameraOff;
  bool get speakerOn => _speakerOn;
  Duration get elapsed =>
      _activeAt == null ? _elapsed : DateTime.now().difference(_activeAt!);
  bool get remoteVideoActive => _remoteVideoActive;
  bool get isEnded => _ended;

  static const _iceTimeout = Duration(seconds: 45);
  static const _answerTimeout = Duration(seconds: 40);

  Future<void> start() async {
    if (_started || _ended) return;
    _started = true;
    try {
      await localRenderer.initialize();
      await remoteRenderer.initialize();
      await _openChannel();
      await _preparePeer();
      await _openMedia();
      _listenCallStatus();
      if (outgoing) {
        _phase = CallPhase.ringing;
        _statusLabel = 'Memanggil…';
        _notify();
        await _sendOffer();
        _offerTimer = Timer.periodic(const Duration(seconds: 2), (_) {
          if (_ended || _remoteSet) return;
          unawaited(_sendOffer());
        });
        _offerTimeout = Timer(_answerTimeout, () {
          if (_ended || _remoteSet) return;
          unawaited(hangUp(reason: 'Tidak dijawab'));
        });
      } else {
        _phase = CallPhase.connecting;
        _statusLabel = 'Menghubungkan…';
        _notify();
        await _broadcast({'type': 'ready'});
        _offerTimeout = Timer(_iceTimeout, () {
          if (_ended || _remoteSet) return;
          _fail('Tidak dapat terhubung ke penelepon.');
        });
      }
    } catch (error) {
      _fail(mapError(error).message);
    }
  }

  // --- WebRTC ---------------------------------------------------------------

  Future<void> _preparePeer() async {
    final iceServers = <Map<String, dynamic>>[
      {'urls': Env.stunUrl},
      if (Env.hasTurn)
        {
          'urls': Env.turnUrl,
          'username': Env.turnUsername,
          'credential': Env.turnCredential,
        },
    ];
    final pc = await createPeerConnection({
      'iceServers': iceServers,
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    });
    _pc = pc;

    pc.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      final payload = {
        'type': 'candidate',
        'candidate': {
          'candidate': candidate.candidate,
          'sdpMid': candidate.sdpMid,
          'sdpMLineIndex': candidate.sdpMLineIndex,
        },
      };
      if (_subscribed) {
        unawaited(_broadcast(payload));
      } else {
        _pendingOutgoing.add(payload);
      }
    };

    pc.onTrack = (event) {
      if (event.streams.isEmpty) return;
      remoteRenderer.srcObject = event.streams.first;
      if (event.track.kind == 'video') {
        _remoteVideoActive = true;
        _notify();
      }
    };

    pc.onConnectionState = (state) {
      switch (state) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _markActive();
        case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
          _statusLabel = 'Koneksi terputus…';
          _notify();
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _fail('Koneksi panggilan gagal.');
        default:
          break;
      }
    };
  }

  Future<void> _openMedia() async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': video
          ? {
              'facingMode': 'user',
              'width': {'ideal': 1280},
              'height': {'ideal': 720},
              'frameRate': {'ideal': 30},
            }
          : false,
    });
    _local = stream;
    if (video) localRenderer.srcObject = stream;
    final pc = _pc;
    if (pc == null) return;
    for (final track in stream.getTracks()) {
      await pc.addTrack(track, stream);
    }
    await Helper.setSpeakerphoneOn(video || _speakerOn);
  }

  void _markActive() {
    if (_ended || _phase == CallPhase.active) return;
    _activeAt = DateTime.now();
    _phase = CallPhase.active;
    _statusLabel = null;
    _offerTimer?.cancel();
    _offerTimeout?.cancel();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _notify());
    _notify();
  }

  // --- Signalling -----------------------------------------------------------

  Future<void> _openChannel() async {
    final channel = _client.channel(
      'call:${call.id}',
      opts: const RealtimeChannelConfig(
        private: true,
        self: true,
        enabled: true,
      ),
    );
    channel.onBroadcast(
      event: 'signal',
      callback: (payload) {
        final inner = payload['payload'];
        final data = inner is Map
            ? Map<String, dynamic>.from(inner)
            : Map<String, dynamic>.from(payload);
        unawaited(_onSignal(data));
      },
    );
    channel.subscribe((status, error) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _subscribed = true;
        for (final pending in _pendingOutgoing) {
          await _broadcast(pending);
        }
        _pendingOutgoing.clear();
      }
    });
    _channel = channel;
  }

  Future<void> _broadcast(Map<String, dynamic> payload) async {
    final channel = _channel;
    if (channel == null || !_subscribed) {
      _pendingOutgoing.add(payload);
      return;
    }
    try {
      await channel.sendBroadcastMessage(event: 'signal', payload: payload);
    } catch (_) {
      // A dropped signal is recovered by the offer retry / ICE restart.
    }
  }

  Future<void> _sendOffer() async {
    final pc = _pc;
    if (pc == null || _ended) return;
    try {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await _broadcast({'type': 'offer', 'sdp': offer.sdp});
    } catch (_) {
      // Ignore transient renegotiation errors; the retry loop tries again.
    }
  }

  Future<void> _onSignal(Map<String, dynamic> data) async {
    if (_ended) return;
    final pc = _pc;
    if (pc == null) return;
    switch (data['type']) {
      case 'ready':
        if (outgoing && !_remoteSet) await _sendOffer();
        return;
      case 'offer':
        if (_remoteSet) return;
        final sdp = data['sdp'] as String?;
        if (sdp == null || sdp.isEmpty) return;
        try {
          await pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
          _remoteSet = true;
          await _flushCandidates();
          final answer = await pc.createAnswer();
          await pc.setLocalDescription(answer);
          await _broadcast({'type': 'answer', 'sdp': answer.sdp});
          _phase = CallPhase.connecting;
          _statusLabel = 'Menghubungkan…';
          _notify();
        } catch (_) {
          _fail('Negosiasi panggilan gagal.');
        }
        return;
      case 'answer':
        if (!outgoing || _remoteSet) return;
        final sdp = data['sdp'] as String?;
        if (sdp == null || sdp.isEmpty) return;
        try {
          await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
          _remoteSet = true;
          await _flushCandidates();
          _phase = CallPhase.connecting;
          _statusLabel = 'Menghubungkan…';
          _notify();
        } catch (_) {
          _fail('Negosiasi panggilan gagal.');
        }
        return;
      case 'candidate':
        final raw = data['candidate'];
        if (raw is! Map) return;
        final candidate = RTCIceCandidate(
          raw['candidate'] as String?,
          raw['sdpMid'] as String?,
          (raw['sdpMLineIndex'] as num?)?.toInt(),
        );
        if (_remoteSet) {
          try {
            await pc.addCandidate(candidate);
          } catch (_) {}
        } else {
          _pendingCandidates.add(candidate);
        }
        return;
      case 'bye':
        await _finish('Panggilan berakhir');
        return;
    }
  }

  Future<void> _flushCandidates() async {
    final pc = _pc;
    if (pc == null) return;
    for (final candidate in _pendingCandidates) {
      try {
        await pc.addCandidate(candidate);
      } catch (_) {}
    }
    _pendingCandidates.clear();
  }

  void _listenCallStatus() {
    _eventsSub = _realtime.listen((event) {
      if (event.kind != RealtimeKind.callChanged) return;
      if (event.record['id'] != call.id) return;
      final status = event.record['status'] as String?;
      if (status == null || _ended) return;
      switch (status) {
        case 'declined':
          unawaited(_finish(outgoing ? 'Ditolak' : 'Panggilan ditolak'));
        case 'cancelled':
          unawaited(_finish('Panggilan dibatalkan'));
        case 'missed':
          unawaited(_finish('Tidak dijawab'));
        case 'ended':
          unawaited(_finish('Panggilan berakhir'));
        case 'active':
          if (outgoing && _phase == CallPhase.ringing) {
            _phase = CallPhase.connecting;
            _statusLabel = 'Menghubungkan…';
            _notify();
          }
      }
    });
  }

  // --- Controls -------------------------------------------------------------

  void toggleMute() {
    _muted = !_muted;
    for (final track in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !_muted;
    }
    _notify();
  }

  void toggleCamera() {
    if (!video) return;
    _cameraOff = !_cameraOff;
    for (final track in _local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = !_cameraOff;
    }
    _notify();
  }

  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    await Helper.setSpeakerphoneOn(_speakerOn);
    _notify();
  }

  Future<void> switchCamera() async {
    if (!video) return;
    final tracks = _local?.getVideoTracks() ?? <MediaStreamTrack>[];
    if (tracks.isEmpty) return;
    try {
      await Helper.switchCamera(tracks.first);
    } catch (_) {}
  }

  Future<void> hangUp({String? reason}) async {
    if (_ended) return;
    final cancel = outgoing && _phase != CallPhase.active;
    try {
      await _repo.action(call.id, cancel ? 'cancel' : 'end');
    } catch (_) {}
    await _broadcast({'type': 'bye'});
    await _finish(
      reason ??
          (cancel
              ? 'Panggilan dibatalkan'
              : outgoing
              ? 'Panggilan berakhir'
              : 'Panggilan berakhir'),
    );
  }

  Future<void> _finish(String label) async {
    if (_ended) return;
    _ended = true;
    _phase = CallPhase.ended;
    _statusLabel = label;
    _elapsed = elapsed;
    _activeAt = null;
    await _teardown();
    _notify();
  }

  void _fail(String message) {
    if (_ended) return;
    _ended = true;
    _phase = CallPhase.failed;
    _errorMessage = message;
    _statusLabel = message;
    _elapsed = elapsed;
    _activeAt = null;
    unawaited(_teardown());
    _notify();
  }

  Future<void> _teardown() async {
    _offerTimer?.cancel();
    _offerTimer = null;
    _offerTimeout?.cancel();
    _offerTimeout = null;
    _ticker?.cancel();
    _ticker = null;
    final sub = _eventsSub;
    _eventsSub = null;
    await sub?.cancel();

    final stream = _local;
    _local = null;
    if (stream != null) {
      for (final track in stream.getTracks()) {
        try {
          await track.stop();
        } catch (_) {}
      }
      await stream.dispose();
    }
    localRenderer.srcObject = null;
    remoteRenderer.srcObject = null;

    final pc = _pc;
    _pc = null;
    if (pc != null) {
      try {
        await pc.close();
      } catch (_) {}
      try {
        await pc.dispose();
      } catch (_) {}
    }

    final channel = _channel;
    _channel = null;
    _subscribed = false;
    if (channel != null) {
      try {
        await _client.removeChannel(channel);
      } catch (_) {}
    }
    try {
      await Helper.setSpeakerphoneOn(false);
    } catch (_) {}
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (!_ended) {
      unawaited(hangUp());
    }
    unawaited(_teardown());
    unawaited(localRenderer.dispose());
    unawaited(remoteRenderer.dispose());
    super.dispose();
  }

  /// Encodes a diagnostic-safe summary without key material or SDP contents.
  String describe() => jsonEncode({
    'call': call.id,
    'kind': call.kind.wire,
    'outgoing': outgoing,
    'phase': _phase.name,
  });
}
