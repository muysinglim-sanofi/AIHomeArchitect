"""WHICH Ayden Studio Web deployment this process is — staging or production.

Until now the Web adapter said "staging" in three different ways at once: a
hard-coded schema (`pwa_staging`), a hard-coded bucket (`pwa-staging-images`),
a hard-coded project ref, and a route prefix (`/pwa/staging`) baked into the
routers at import time. That was correct while only one deployment existed. A
production deployment cannot be a copy of those constants with the words
changed — the copy would drift, and a drifted copy of a payment path is how a
production process ends up writing into a staging table.

So the four facts live here, together, keyed by ONE variable:

    PWA_TARGET = staging (default) | production

and every consumer asks this module instead of holding its own constant.

WHAT DOES NOT CHANGE. `PWA_TARGET` unset behaves exactly as before: staging
schema, staging bucket, staging project ref, `/pwa/staging` routes. The staging
deployment therefore needs no new variable and cannot be altered by this file.

FAIL CLOSED, BOTH WAYS. A target is only usable if the Supabase URL in the
environment belongs to THAT target's project. A staging process pointed at
production refuses; a production process pointed at staging refuses. The check
is a substring match on the project ref, which is not a secret and is already
present in the repository (`lib/core/env/app_environment.dart`,
`pwa_environment.dart`).

Nothing here reads a credential, opens a connection, or performs I/O.
"""
from __future__ import annotations

import os
from dataclasses import dataclass

#: The two Supabase projects this product has. Not secrets; both already appear
#: in tracked source, and naming them is what makes the guard checkable.
STAGING_REF = "eedcahzekpgxvvfxufbk"
PRODUCTION_REF = "vtxkciupyafukhdsgxgw"

STAGING = "staging"
PRODUCTION = "production"
TARGETS = (STAGING, PRODUCTION)


class PwaTargetError(RuntimeError):
    """The requested target cannot be served by this environment."""


@dataclass(frozen=True)
class PwaTarget:
    """Everything that differs between the two Web deployments."""

    name: str
    project_ref: str
    #: PostgREST schema holding projects / visions / messages / payway rows.
    schema: str
    #: Private Storage bucket holding originals and renders.
    bucket: str
    #: Route prefix of the Web adapter. The payments router hangs below it.
    prefix: str

    @property
    def is_production(self) -> bool:
        return self.name == PRODUCTION

    @property
    def payments_prefix(self) -> str:
        return f"{self.prefix}/payments"

    #: The project ref this target must NOT be pointed at.
    @property
    def foreign_ref(self) -> str:
        return PRODUCTION_REF if self.name == STAGING else STAGING_REF


_TARGETS = {
    STAGING: PwaTarget(
        name=STAGING,
        project_ref=STAGING_REF,
        schema="pwa_staging",
        bucket="pwa-staging-images",
        prefix="/pwa/staging",
    ),
    PRODUCTION: PwaTarget(
        name=PRODUCTION,
        project_ref=PRODUCTION_REF,
        # A production deployment gets clean names. `pwa_staging` in production
        # would be a lie that every future reader has to decode.
        schema="pwa",
        bucket="pwa-images",
        prefix="/pwa",
    ),
}


def target_name() -> str:
    """The requested target. Unset = staging, so nothing existing changes."""
    name = (os.environ.get("PWA_TARGET") or STAGING).strip().lower()
    if name not in _TARGETS:
        raise PwaTargetError(
            f"PWA_TARGET={name!r} is not a target. Use one of {TARGETS!r}.")
    return name


def current() -> PwaTarget:
    """The resolved target. Read on every call: a process that is re-pointed
    mid-life must not keep serving the target it booted with."""
    return _TARGETS[target_name()]


def assert_url_matches(url: str, *, where: str = "environment") -> PwaTarget:
    """Refuse a SUPABASE_URL that does not belong to the requested target.

    Returns the target when it does, so a caller can do both in one line.
    """
    t = current()
    url = (url or "").strip()
    if not url:
        raise PwaTargetError(
            f"SUPABASE_URL is empty in the {where} — refusing to serve "
            f"{t.name} against an unknown project.")
    if t.foreign_ref in url:
        raise PwaTargetError(
            f"SUPABASE_URL in the {where} points at {t.foreign_ref} while "
            f"PWA_TARGET={t.name}. Refusing (fail closed).")
    if t.project_ref not in url:
        raise PwaTargetError(
            f"SUPABASE_URL in the {where} does not carry the {t.name} project "
            f"ref ({t.project_ref}). Refusing (fail closed).")
    return t
