/// Non-web stub. Reports unsupported; the controller then takes the server-side
/// checkout path, which is what every widget test exercises.
library;

import 'pwa_aba_plugin.dart';

PwaAbaPlugin createPlugin() => const PwaNoopAbaPlugin();
