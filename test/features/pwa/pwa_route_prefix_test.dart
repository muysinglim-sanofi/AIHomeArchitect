// The production route prefix (`app.aydenstudio.com/kh`). The prefix is removed
// where the browser URL is read and restored where it is written; the route
// model never sees it. PREFIX01-08.

import 'package:ai_home_architect/features/pwa/application/pwa_route.dart';
import 'package:ai_home_architect/features/pwa/application/pwa_url_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

PwaRoute _read(String browser, [String prefix = '/kh']) =>
    PwaRoute.parse(pwaStripRoutePrefix(Uri.parse(browser), prefix));

void main() {
  test('PREFIX01: /kh and /kh/ are Home', () {
    expect(_read('/kh'), PwaRoute.home);
    expect(_read('/kh/'), PwaRoute.home);
  });

  test('PREFIX02: deep links under /kh open their page (refresh keeps them)', () {
    expect(_read('/kh/projects'), PwaRoute.projects);
    expect(_read('/kh/create'), PwaRoute.create);
    expect(_read('/kh/profile'), PwaRoute.profile);
    expect(
      _read('/kh/projects/p1/architect?vision=v2'),
      const PwaRoute(PwaPage.architect, projectId: 'p1', visionId: 'v2'),
    );
    expect(
      _read('/kh/projects/p1/reveal?vision=v2'),
      const PwaRoute(PwaPage.reveal, projectId: 'p1', visionId: 'v2'),
    );
  });

  test('PREFIX03: every route is written back under /kh, and round-trips', () {
    const routes = [
      PwaRoute.home,
      PwaRoute.create,
      PwaRoute.projects,
      PwaRoute.profile,
      PwaRoute(PwaPage.draft, projectId: 'p1'),
      PwaRoute(PwaPage.architect, projectId: 'p1', visionId: 'v2'),
      PwaRoute(PwaPage.reveal, projectId: 'p1', visionId: 'v2'),
    ];
    for (final r in routes) {
      final written = pwaApplyRoutePrefix(r.location, '/kh');
      expect(written.startsWith('/kh'), isTrue, reason: written);
      expect(_read(written), r, reason: written);
    }
    expect(pwaApplyRoutePrefix('/', '/kh'), '/kh');
    expect(pwaApplyRoutePrefix('/?a=b', '/kh'), '/kh?a=b');
  });

  test('PREFIX04: a pre-prefix bookmark still opens its page', () {
    expect(
      _read('/projects/p1/architect'),
      const PwaRoute(PwaPage.architect, projectId: 'p1'),
    );
  });

  test('PREFIX05: a lookalike segment is NOT the prefix', () {
    expect(
      pwaStripRoutePrefix(Uri.parse('/khmer/projects'), '/kh').path,
      '/khmer/projects',
    );
  });

  test('PREFIX06: no prefix = the root deployments, byte-for-byte unchanged', () {
    for (final l in ['/', '/projects', '/projects/p1/architect?vision=v']) {
      expect(pwaApplyRoutePrefix(l, ''), l);
      expect(pwaStripRoutePrefix(Uri.parse(l), '').toString(), l);
    }
  });

  test('PREFIX07: the query survives the strip', () {
    final u = pwaStripRoutePrefix(Uri.parse('/kh?code=abc'), '/kh');
    expect(u.path, '/');
    expect(u.queryParameters['code'], 'abc');
  });

  test('PREFIX08: only empty or one lowercase segment is a valid prefix', () {
    expect(pwaRoutePrefix(''), '');
    expect(pwaRoutePrefix(' /kh '), '/kh');
    for (final bad in ['kh', '/kh/', '/KH', '/kh/x', '//kh', '/k']) {
      expect(() => pwaRoutePrefix(bad), throwsArgumentError, reason: bad);
    }
  });
}
