/// Build-time configuration.
///
/// Secrets (service_role key, FCM service account, TURN secret, signing key)
/// must never be passed here. Only publishable values belong in the APK.
abstract final class Env {
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://supabase.adoetz52.my.id',
  );

  // Publishable anon key. Access is constrained by RLS, never by secrecy.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlLWRlbW8iLCJpYXQiOjE3ODE0MjkzOTMsImV4cCI6MjA4Mjc1ODQwMH0.qgQ3hxL9JgRhZ-0vuIAG-myu8w5UeWkG1iNrsjqDvR0',
  );

  static const String stunUrl = String.fromEnvironment(
    'STUN_URL',
    defaultValue: 'stun:stun.l.google.com:19302',
  );

  static const String turnUrl = String.fromEnvironment('TURN_URL');
  static const String turnUsername = String.fromEnvironment('TURN_USERNAME');
  static const String turnCredential = String.fromEnvironment(
    'TURN_CREDENTIAL',
  );

  static bool get hasTurn => turnUrl.isNotEmpty;

  static const int callAnswerTimeoutSeconds = 40;
  static const int callDisconnectGraceSeconds = 25;
  static const int messagePageSize = 40;
  static const int inviteInitialMaxUses = 1;
  static const int inviteExpiryDays = 7;

  static const int imageMaxBytes = 15 * 1024 * 1024;
  static const int videoMaxBytes = 100 * 1024 * 1024;
  static const int documentMaxBytes = 25 * 1024 * 1024;
  static const int voiceMaxSeconds = 10 * 60;

  static const String avatarsBucket = 'avatars';
  static const String attachmentsBucket = 'attachments';

  /// Calls are feature-flagged until the WebRTC gate passes on real devices.
  static const bool callsEnabled = bool.fromEnvironment(
    'CALLS_ENABLED',
    defaultValue: true,
  );

  /// Put the app into read-only cached mode when the backend is unreachable.
  static const bool allowOfflineMode = true;
}
