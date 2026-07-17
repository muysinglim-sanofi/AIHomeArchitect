/// DIAGNOSTIC BUILD ONLY — branch `qa/identity-diag`. READ-ONLY identity/billing snapshot.
///
/// NO business logic, NO writes, NO mutation. It only READS:
///   • Supabase auth (current user_id / is_anonymous / has_session)
///   • RevenueCat (app_user_id / original_app_user_id / active entitlement / product) via
///     Purchases.appUserID + getCustomerInfo() — both read-only SDK calls
///   • Backend /me/status snapshot already loaded in meStatusProvider (availableCredits =
///     wallet, activePassId, activeProductId, accessSource, planType, canGenerate, …)
///
/// Purpose: identify the EXACT active identity on-device without a Mac. A "Copy" button puts
/// the whole snapshot on the clipboard to paste back. NEVER merge this branch to launch —
/// the launch branch (wave4-design-spine) does not contain this panel.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/providers/me_status_provider.dart';

class IdentityDiagPanel extends ConsumerStatefulWidget {
  const IdentityDiagPanel({super.key});

  @override
  ConsumerState<IdentityDiagPanel> createState() => _IdentityDiagPanelState();
}

class _IdentityDiagPanelState extends ConsumerState<IdentityDiagPanel> {
  String _rc = 'RevenueCat: loading…';

  @override
  void initState() {
    super.initState();
    _loadRc();
  }

  Future<void> _loadRc() async {
    final b = StringBuffer();
    try {
      b.writeln('rc_app_user_id: ${await Purchases.appUserID}');
    } catch (e) {
      b.writeln('rc_app_user_id: ERR ${e.runtimeType}');
    }
    try {
      final info = await Purchases.getCustomerInfo();
      b.writeln('rc_original_app_user_id: ${info.originalAppUserId}');
      final active = info.entitlements.active;
      b.writeln(
          'rc_active_entitlements: ${active.isEmpty ? "none" : active.keys.join(",")}');
      b.writeln(
          'rc_active_subscriptions: ${info.activeSubscriptions.isEmpty ? "none" : info.activeSubscriptions.join(",")}');
      for (final e in active.values) {
        b.writeln(
            'rc_ent[${e.identifier}]: product=${e.productIdentifier} expires=${e.expirationDate} willRenew=${e.willRenew}');
      }
    } catch (e) {
      b.writeln('rc_customerInfo: ERR ${e.runtimeType}');
    }
    if (mounted) setState(() => _rc = b.toString().trim());
  }

  String _snapshot() {
    final auth = Supabase.instance.client.auth;
    final st = ref.read(meStatusProvider);
    final b = StringBuffer();
    b.writeln('===== IDENTITY DIAGNOSTIC =====');
    b.writeln('-- SUPABASE --');
    b.writeln('user_id: ${auth.currentUser?.id}');
    b.writeln('is_anonymous: ${auth.currentUser?.isAnonymous}');
    b.writeln('has_session: ${auth.currentSession != null}');
    b.writeln('-- REVENUECAT --');
    b.writeln(_rc);
    b.writeln('-- BACKEND /me/status --');
    if (st == null) {
      b.writeln('(status not loaded yet — pull to refresh Home once)');
    } else {
      b.writeln('role: ${st.role}   access_source: ${st.accessSource}');
      b.writeln('can_generate: ${st.canGenerate}   gate_reason: "${st.gateReason}"');
      b.writeln('wallet_available_credits: ${st.availableCredits}');
      b.writeln('active_pass_id: ${st.activePassId}');
      b.writeln('active_product_id: ${st.activeProductId}');
      b.writeln('plan_type: ${st.planType}   has_active_pass: ${st.hasActivePass}');
      b.writeln('pass_expires_at: ${st.passExpiresAt}');
      b.writeln('remaining_free: ${st.remainingFreeGenerations}');
      b.writeln('needs_restore: ${st.needsRestore}');
    }
    return b.toString().trim();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(meStatusProvider); // rebuild when status loads/refreshes
    final text = _snapshot();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.orange, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Text('🔧 IDENTITY DIAGNOSTIC · internal build',
                      style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.refresh, color: Colors.orange, size: 20),
                  onPressed: () async {
                    await _loadRc();
                    await ref.read(meStatusProvider.notifier).refresh();
                  },
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.copy, color: Colors.orange, size: 20),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _snapshot()));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Diagnostic copié')),
                      );
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            SelectableText(
              text,
              style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'monospace',
                  fontSize: 11,
                  height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}
