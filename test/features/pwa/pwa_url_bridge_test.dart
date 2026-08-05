// Batch 3.4b — the in-memory history bridge used by tests + the non-web VM.
// Proves the stack semantics (HISTORY01-05) the real History-API bridge mirrors:
// push adds an entry, replace does not, Back/Forward move the cursor and notify.

import 'package:ai_home_architect/features/pwa/application/pwa_url_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('HISTORY01: push adds an entry and moves current', () {
    final b = FakePwaUrlBridge('/');
    b.push('/projects');
    expect(b.current().path, '/projects');
    expect(b.historyLength, 2);
    expect(b.ops, ['push:/projects']);
  });

  test('HISTORY02: replace swaps current WITHOUT adding an entry', () {
    final b = FakePwaUrlBridge('/');
    b.push('/projects/a/draft'); // len 2
    b.replace('/projects/a/architect'); // len still 2
    expect(b.current().path, '/projects/a/architect');
    expect(b.historyLength, 2);
    expect(b.ops.last, 'replace:/projects/a/architect');
  });

  test('HISTORY03: Back moves to the previous entry and notifies popstate', () {
    final b = FakePwaUrlBridge('/');
    final seen = <String>[];
    b.onPop((u) => seen.add(u.path));
    b.push('/projects');
    b.push('/projects/a/architect');
    b.back();
    expect(b.current().path, '/projects');
    expect(seen, ['/projects']);
  });

  test('HISTORY04: Forward re-advances and notifies popstate', () {
    final b = FakePwaUrlBridge('/');
    final seen = <String>[];
    b.onPop((u) => seen.add(u.path));
    b.push('/projects');
    b.back(); // → /
    b.forward(); // → /projects
    expect(b.current().path, '/projects');
    expect(seen, ['/', '/projects']);
  });

  test('HISTORY05: push after Back truncates the forward entries', () {
    final b = FakePwaUrlBridge('/');
    b.push('/projects'); // [/ , /projects]
    b.push('/projects/a/architect'); // [/, /projects, /architect]
    b.back(); // cursor at /projects
    b.push('/projects/b/draft'); // forward (/architect) dropped
    expect(b.current().path, '/projects/b/draft');
    expect(b.historyLength, 3);
    b.forward(); // nothing ahead → stays
    expect(b.current().path, '/projects/b/draft');
  });

  test('query is preserved in current()', () {
    final b = FakePwaUrlBridge('/projects/a/architect?vision=v9');
    expect(b.current().queryParameters['vision'], 'v9');
  });
}
