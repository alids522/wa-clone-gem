import 'package:adoetz_chat/core/models/message.dart';
import 'package:adoetz_chat/core/services/call_repository.dart';
import 'package:adoetz_chat/core/utils/formatters.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID');
  });

  group('Formatters', () {
    test('formats byte sizes', () {
      expect(Formatters.bytes(512), '512 B');
      expect(Formatters.bytes(2048), '2.0 KB');
      expect(Formatters.bytes(5 * 1024 * 1024), '5.0 MB');
    });

    test('formats call durations', () {
      expect(Formatters.duration(const Duration(seconds: 5)), '0:05');
      expect(
        Formatters.duration(const Duration(minutes: 2, seconds: 7)),
        '2:07',
      );
      expect(
        Formatters.duration(const Duration(hours: 1, minutes: 3, seconds: 9)),
        '1:03:09',
      );
    });

    test('collapses whitespace and truncates previews', () {
      expect(Formatters.messagePreview('  halo\n\tdunia  '), 'halo dunia');
      expect(Formatters.messagePreview('a' * 70, max: 10), '${'a' * 10}…');
    });

    test('describes call outcomes', () {
      expect(
        Formatters.callOutcome(
          direction: 'incoming',
          status: 'missed',
          duration: Duration.zero,
        ),
        'Panggilan tak terjawab',
      );
      expect(
        Formatters.callOutcome(
          direction: 'outgoing',
          status: 'ended',
          duration: const Duration(minutes: 1),
        ),
        '1 mnt',
      );
    });
  });

  group('ChatMessage reactions', () {
    ChatMessage sample() => ChatMessage(
      id: 'm1',
      clientMessageId: 'c1',
      conversationId: 'conv',
      senderId: 'peer',
      createdAt: DateTime.utc(2026, 10, 28, 10),
      kind: MessageKind.text,
      status: MessageStatus.read,
      envelope: const MessageEnvelope(body: 'halo'),
      reactions: const {
        '👍': ['me', 'peer'],
        '❤️': ['peer'],
      },
    );

    test('survive the local database round trip', () {
      final restored = ChatMessage.fromLocalMap(sample().toLocalMap());
      expect(restored.reactions['👍'], ['me', 'peer']);
      expect(restored.reactions['❤️'], ['peer']);
      expect(restored.body, 'halo');
    });

    test('fall back to an empty map on corrupt data', () {
      final map = sample().toLocalMap()..['reactions'] = 'not json';
      expect(ChatMessage.fromLocalMap(map).reactions, isEmpty);
    });
  });

  group('CallKind', () {
    test('round-trips wire values', () {
      expect(CallKind.fromWire('voice'), CallKind.voice);
      expect(CallKind.fromWire('video'), CallKind.video);
      expect(CallKind.fromWire('unknown'), CallKind.voice);
      expect(CallKind.video.wire, 'video');
    });
  });
}
