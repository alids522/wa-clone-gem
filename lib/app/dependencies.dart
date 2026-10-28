import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env.dart';
import '../core/crypto/e2ee_service.dart';
import '../core/crypto/media_crypto.dart';
import '../core/services/admin_repository.dart';
import '../core/services/auth_repository.dart';
import '../core/services/call_repository.dart';
import '../core/services/chat_repository.dart';
import '../core/services/media_service.dart';
import '../core/services/profile_repository.dart';
import '../core/services/push_service.dart';
import '../core/services/realtime_service.dart';
import '../core/storage/local_database.dart';
import '../core/storage/secure_store.dart';

class AppDependencies {
  const AppDependencies({
    required this.client,
    required this.db,
    required this.secure,
    required this.e2ee,
    required this.media,
    required this.auth,
    required this.profiles,
    required this.chat,
    required this.calls,
    required this.admin,
    required this.realtime,
    required this.push,
    required this.prefs,
  });

  final SupabaseClient client;
  final LocalDatabase db;
  final SecureStore secure;
  final E2eeService e2ee;
  final MediaService media;
  final AuthRepository auth;
  final ProfileRepository profiles;
  final ChatRepository chat;
  final CallRepository calls;
  final AdminRepository admin;
  final RealtimeService realtime;
  final PushService push;
  final SharedPreferences prefs;

  static Future<AppDependencies> create() async {
    final secure = SecureStore();
    final password = await secure.databasePassword();
    final db = await LocalDatabase.open(password);
    final prefs = await SharedPreferences.getInstance();

    await Supabase.initialize(
      url: Env.supabaseUrl,
      anonKey: Env.supabaseAnonKey,
      // The instance hosts another application in `public`, so this app keeps
      // all of its tables in its own schema. PostgREST selects it per request
      // through these headers.
      postgrestOptions: const PostgrestClientOptions(schema: Env.dbSchema),
    );
    final client = Supabase.instance.client;

    final e2ee = E2eeService(client: client, db: db, secure: secure);
    final media = MediaService(client: client, crypto: MediaCrypto());
    final auth = AuthRepository(client);
    final profiles = ProfileRepository(
      client: client,
      media: media,
      e2ee: e2ee,
    );
    final chat = ChatRepository(
      client: client,
      db: db,
      e2ee: e2ee,
      media: media,
      profiles: profiles,
    );
    final calls = CallRepository(client);
    final admin = AdminRepository(client);
    final realtime = RealtimeService(client);
    final push = PushService(client: client, secure: secure);
    try {
      await push.initialize();
    } catch (_) {
      // Push is optional; the app remains usable without Firebase config.
    }

    return AppDependencies(
      client: client,
      db: db,
      secure: secure,
      e2ee: e2ee,
      media: media,
      auth: auth,
      profiles: profiles,
      chat: chat,
      calls: calls,
      admin: admin,
      realtime: realtime,
      push: push,
      prefs: prefs,
    );
  }
}
