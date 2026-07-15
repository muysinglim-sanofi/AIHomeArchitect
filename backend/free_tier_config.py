"""
Free Trial — configuration CENTRALISÉE des générations gratuites (FT1, 2026-07-15).

SOURCE DE VÉRITÉ UNIQUE côté Python pour le modèle produit :

    « 3 générations gratuites maximum :
        - 1 immédiatement, sans création de compte visible ;
        - 2 de plus après création réelle d'un NOUVEAU compte. »

Ces trois constantes remplacent les valeurs « 3 » jadis codées en dur à plusieurs
endroits divergents (billing.TRIAL_CREDITS, quota.FREE_TIER_LIMIT). Le miroir SQL
vit dans la fonction `public.billing_free_config()` (migration
20260717_ft1a_freetrial_signup_bonus.sql). Le validateur offline
`_freetrial_validation.py` VÉRIFIE que Python et SQL restent cohérents.

⚠️ Ne jamais réintroduire un littéral « 3 » de free-tier ailleurs : importer ces
constantes. L'AUTORITÉ d'enforcement reste le SQL (billing_try_hold +
billing_grant_signup_bonus) ; ces constantes Python pilotent la projection et
l'affichage.
"""

from __future__ import annotations

# 1re génération offerte à l'identité anonyme, sans compte visible.
ANONYMOUS_FREE_GENERATIONS = 1

# Bonus accordé UNE seule fois après création réelle d'un nouveau compte.
ACCOUNT_CREATION_FREE_BONUS = 2

# Plafond gratuit total (dérivé — jamais saisi à la main).
TOTAL_FREE_GENERATIONS = ANONYMOUS_FREE_GENERATIONS + ACCOUNT_CREATION_FREE_BONUS  # = 3

# Valeur d'enforcement du trial anonyme AVANT le lancement FT2 : billing_try_hold
# (SQL) accorde littéralement 3 tant que la migration 20260718_ft1b n'est PAS
# appliquée. L'AFFICHAGE (billing.TRIAL_CREDITS) doit refléter CETTE valeur pendant
# toute la fenêtre FT1 pour rester == enforcement, puis basculer à
# ANONYMOUS_FREE_GENERATIONS AU MÊME INSTANT que FT2 (flag + ft1b, atomiques).
# → billing.TRIAL_CREDITS est gaté sur FREE_TRIAL_SIGNUP_BONUS_ENABLED.
PRE_FT2_ANON_FREE_GENERATIONS = 3
