/// FT2-B spike — plain, non-esthetic control screen.
///
/// Seven manual actions (A–G). Nothing runs automatically at boot. Every Apple
/// phase is confirmed first, guarded against the protected account, and — for
/// Phase B/C — gated by the pure state machine so steps cannot be skipped.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ft2b_spike_auth.dart';
import 'ft2b_spike_models.dart';

class Ft2bSpikeScreen extends StatefulWidget {
  const Ft2bSpikeScreen({super.key});

  @override
  State<Ft2bSpikeScreen> createState() => _Ft2bSpikeScreenState();
}

class _Ft2bSpikeScreenState extends State<Ft2bSpikeScreen> {
  final Ft2bSpikeAuth _auth = Ft2bSpikeAuth();
  static const JsonEncoder _pretty = JsonEncoder.withIndent('  ');

  SpikePhase _phase = SpikePhase.start;
  SpikeAuthSnapshot? _snapshot;
  PhaseBResult? _phaseB;
  PhaseCResult? _phaseC;
  VerifySignInResult? _verify;
  String? _permanentBId; // remembered in-memory only
  bool _busy = false;
  String _status = 'Idle. Nothing has run.';

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _auth.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() => _snapshot = _auth.snapshot());
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Proceed'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  /// Belt-and-braces: refuse if the isolated session ever resolves to the
  /// protected production account. Returns true if it is SAFE to proceed.
  bool _guardProtected() {
    if (isProtectedAccount(_auth.snapshot().userId)) {
      setState(
        () => _status =
            'REFUSED: isolated session resolved to the PROTECTED account. '
            'No action taken.',
      );
      return false;
    }
    return true;
  }

  Future<void> _run(String label, Future<void> Function() body) async {
    if (_busy) {
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Running: $label…';
    });
    try {
      await body();
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  // ── A/B: create isolated anon ──────────────────────────────────────────────

  Future<void> _createAnon() => _run('create isolated anon', () async {
    if (!_guardProtected()) {
      return;
    }
    final id = await _auth.ensureAnonymous();
    if (!mounted) {
      return;
    }
    setState(() {
      _phase = SpikePhase.anonReady;
      _status = 'Isolated anonymous user ready: ${id ?? '(none)'}';
    });
    _refresh();
  });

  // ── C: Phase B ─────────────────────────────────────────────────────────────

  Future<void> _phaseBLink() async {
    final snap = _auth.snapshot();
    if (!canRunPhaseB(_phase, isAnonymous: snap.isAnonymous)) {
      setState(
        () => _status =
            'Blocked: Phase B needs a fresh ANONYMOUS user (tap "Create '
            'isolated anonymous user" first).',
      );
      return;
    }
    if (!_guardProtected()) {
      return;
    }
    final ok = await _confirm(
      'Phase B — link a NEW Apple identity',
      'This opens the Apple dialog and links a NEW Apple identity to the '
          'isolated anonymous user. Use an Apple ID that is NOT yet linked.',
    );
    if (!ok) {
      return;
    }
    await _run('Phase B link', () async {
      final res = await _auth.linkNewAppleIdentity();
      if (!mounted) {
        return;
      }
      setState(() {
        _phaseB = res;
        _permanentBId = res.userIdAfter;
        _phase = res.linkSucceeded ? SpikePhase.phaseBDone : _phase;
        _status = res.linkSucceeded
            ? 'Phase B done. Permanent id: ${res.userIdAfter}'
            : 'Phase B link failed (captured). See report.';
      });
      _refresh();
    });
  }

  // ── D: prepare Phase C ─────────────────────────────────────────────────────

  Future<void> _prepareC() async {
    if (!canPreparePhaseC(_phase)) {
      setState(
        () => _status =
            'Blocked: run Phase B (successful new link) before preparing '
            'Phase C.',
      );
      return;
    }
    if (!_guardProtected()) {
      return;
    }
    final ok = await _confirm(
      'Prepare Phase C — new anonymous user',
      'This signs out the spike session (LOCAL only) and creates a fresh '
          'anonymous user. No account or row is deleted. The Phase B UUID stays '
          'only in memory.',
    );
    if (!ok) {
      return;
    }
    await _run('prepare Phase C', () async {
      final newId = await _auth.prepareNewAnonymous();
      if (!mounted) {
        return;
      }
      final differs = newId != null && newId != _permanentBId;
      setState(() {
        _phase = SpikePhase.phaseCPrepared;
        _status = differs
            ? 'Fresh anon ready ($newId), distinct from Phase B. Ready for '
                  'Phase C.'
            : 'WARNING: new anon id not distinct from Phase B — inspect before '
                  'Phase C.';
      });
      _refresh();
    });
  }

  // ── E: Phase C ─────────────────────────────────────────────────────────────

  Future<void> _phaseCLink() async {
    if (!canRunPhaseC(_phase)) {
      setState(
        () => _status =
            'Blocked: prepare Phase C (fresh anon) before linking the same '
            'Apple identity.',
      );
      return;
    }
    if (!_guardProtected()) {
      return;
    }
    final ok = await _confirm(
      'Phase C — link the SAME Apple identity',
      'This opens the Apple dialog again. Use the SAME Apple ID as Phase B. '
          'The link is EXPECTED to fail; the spike captures the exact server '
          'response and confirms your session survives.',
    );
    if (!ok) {
      return;
    }
    await _run('Phase C link', () async {
      final res = await _auth.linkSameAppleIdentity();
      if (!mounted) {
        return;
      }
      setState(() {
        _phaseC = res;
        _phase = SpikePhase.phaseCDone;
        _status = res.linkSucceeded
            ? 'Phase C link SUCCEEDED (unexpected — captured).'
            : 'Phase C link failed as hypothesized (captured). See report.';
      });
      _refresh();
    });
  }

  // ── F: verify existing-account sign-in ─────────────────────────────────────

  Future<void> _verifySignIn() async {
    if (!_guardProtected()) {
      return;
    }
    final ok = await _confirm(
      'Verify existing-account sign-in',
      'This signs in (NOT link) with the SAME Apple ID to prove it belongs to '
          'the Phase B account. This changes the active spike session.',
    );
    if (!ok) {
      return;
    }
    await _run('verify sign-in', () async {
      final res = await _auth.verifyExistingSignIn(_permanentBId);
      if (!mounted) {
        return;
      }
      setState(() {
        _verify = res;
        _status = res.matchesPhaseB
            ? 'Verified: Apple identity belongs to the Phase B account.'
            : 'Verify result captured (no match / error). See report.';
      });
      _refresh();
    });
  }

  // ── G: copy sanitized report ───────────────────────────────────────────────

  SpikeReport _buildReport() => SpikeReport(
    testUserId: _auth.snapshot().userId,
    phaseB: _phaseB,
    phaseC: _phaseC,
    verify: _verify,
    capturedAtIso: DateTime.now().toUtc().toIso8601String(),
  );

  Future<void> _copyReport() async {
    final json = _pretty.convert(_buildReport().toSanitizedJson());
    await Clipboard.setData(ClipboardData(text: json));
    if (!mounted) {
      return;
    }
    setState(() => _status = 'Sanitized report copied to clipboard.');
  }

  // ── UI ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    final reportJson = _pretty.convert(_buildReport().toSanitizedJson());
    return Scaffold(
      appBar: AppBar(title: const Text('FT2-B Apple Identity Link — SPIKE')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _stateCard(snap),
              const SizedBox(height: 12),
              Text('Phase: ${_phase.name}'),
              const SizedBox(height: 4),
              Text(_status),
              const Divider(height: 24),
              _btn('A/B · Create isolated anonymous user', _createAnon),
              _btn('C · Phase B — Link NEW Apple identity', _phaseBLink),
              _btn('D · Prepare Phase C — New anonymous user', _prepareC),
              _btn('E · Phase C — Link SAME Apple identity', _phaseCLink),
              _btn('F · Verify existing-account sign-in', _verifySignIn),
              _btn('G · Copy sanitized report', _copyReport),
              const Divider(height: 24),
              const Text('Sanitized report (live):'),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: const Color(0xFFF1F1F1),
                child: Text(
                  reportJson,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stateCard(SpikeAuthSnapshot? snap) {
    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFFEAF2FF),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Isolated session state',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text('user_id: ${snap?.userId ?? '(none)'}'),
          Text('isAnonymous: ${snap?.isAnonymous ?? false}'),
          Text('hasSession: ${snap?.hasSession ?? false}'),
          Text('identities: ${snap?.identities.join(', ') ?? ''}'),
          if (_permanentBId != null) Text('phase_b_permanent: $_permanentBId'),
        ],
      ),
    );
  }

  Widget _btn(String label, Future<void> Function() onTap) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ElevatedButton(
        onPressed: _busy ? null : () => onTap(),
        child: Text(label, textAlign: TextAlign.center),
      ),
    );
  }
}
