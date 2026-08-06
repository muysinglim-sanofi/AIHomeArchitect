"""Static server for the built PWA — with the SPA fallback the app requires.

Why this exists
---------------
The PWA uses real browser URLs (`/projects/{id}/architect`, `/projects/{id}/reveal`).
Those are ROUTES, not files. A plain `python -m http.server` looks for a file at
that path, finds none and answers 404 — so the app works until the first refresh
and then appears to be broken by F5. It is not: nothing ever reached the app.

Any real host needs the same rule, so it is written down here rather than
rediscovered: serve the file when one exists, otherwise serve `index.html` and
let the app read the URL. (Netlify `_redirects`, Vercel `rewrites`,
nginx `try_files $uri /index.html` — same rule, different syntax.)

    python tool/serve_pwa_web.py [port] [--directory build/web]
"""
from __future__ import annotations

import argparse
import os
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class SpaRequestHandler(SimpleHTTPRequestHandler):
    """Serves real files; falls back to index.html for unknown paths."""

    def send_head(self):  # noqa: D102 - stdlib override
        path = self.translate_path(self.path)
        # A directory or an existing file is served normally. Anything else is a
        # client-side route: hand back the app shell and let it route itself.
        if not os.path.exists(path) and "." not in os.path.basename(path):
            self.path = "/index.html"
        return super().send_head()

    def end_headers(self):  # noqa: D102 - stdlib override
        # The shell must never be cached, or a rebuilt app keeps serving the old
        # main.dart.js after a refresh.
        self.send_header("Cache-Control", "no-store")
        super().end_headers()

    def log_message(self, fmt, *args):  # noqa: D102 - quieter console
        if "404" in (fmt % args):
            super().log_message(fmt, *args)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("port", nargs="?", type=int, default=8104)
    parser.add_argument("--directory", default="build/web")
    args = parser.parse_args()

    handler = partial(SpaRequestHandler, directory=args.directory)
    server = ThreadingHTTPServer(("127.0.0.1", args.port), handler)
    print(f"PWA served from {args.directory} on http://127.0.0.1:{args.port} "
          f"(SPA fallback enabled)")
    server.serve_forever()


if __name__ == "__main__":
    main()
