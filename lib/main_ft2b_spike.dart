/// FT2-B spike — SEPARATE entrypoint. Build with:
///   flutter build ipa -t lib/main_ft2b_spike.dart      (do NOT run yet — FT2-B0)
///
/// This entrypoint is DELIBERATELY minimal and shares NOTHING with the normal
/// `lib/main.dart`:
///   • loads dotenv (same as the app);
///   • initializes Supabase with the SAME url/anon key BUT an ISOLATED session
///     store (SpikeSecureLocalStorage → Keychain key `sb_supabase_session_ft2b_spike`,
///     never the real `sb_supabase_session`);
///   • runs ONLY Ft2bSpikeApp.
///
/// It NEVER: calls the normal main(), initializes RevenueCat/Firebase/push/
/// notifications/PendingRecovery, mounts meStatusProvider, constructs the FT2-A
/// IdentityService, or calls any /identity, /generate or /refine endpoint. No
/// action runs automatically at boot — every step is a manual button tap.
library;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'debug/ft2b_spike/ft2b_spike_app.dart';
import 'debug/ft2b_spike/ft2b_spike_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: '.env');
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL'] ?? '',
    anonKey: dotenv.env['SUPABASE_ANON_KEY'] ?? '',
    authOptions: FlutterAuthClientOptions(
      localStorage: SpikeSecureLocalStorage(),
    ),
  );
  runApp(const Ft2bSpikeApp());
}
