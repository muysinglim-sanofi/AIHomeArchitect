"""Refine Engine V2 — pipeline conversationnel multi-changements (MOTEUR 2, ISOLÉ).

Contrat produit (docs/REFINE_ENGINE_V2.md §9) : 1 action user = 1 génération = 1
image affichée ; aucune génération cachée ; retry uniquement sur décision user.

⚠️ FRONTIÈRE : ce package NE TOUCHE JAMAIS le Moteur 1 (V1 /generate, composer,
DNA, preserve, structural identity, switch). Il n'appelle images.edit que via son
propre exécuteur. Voir mémoire two-engine-frozen-zone.
"""
