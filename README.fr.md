# Conso Claude

Consommation Claude (plan Max) dans la **barre de menus macOS** : `✳ 70 %` en
permanence — le pourcentage **restant** de la session — popover discret au clic
(barres animées, sparkline 6 h, prédiction « empty ~HH:MM »), et un petit avion
corail qui traverse l'écran avec une phrase d'encouragement quand il te reste
50 / 25 / 10 %.

<p align="center">
  <img src="assets/popover.png" width="380" alt="Le popover : session 5 h, hebdo tous modèles et hebdo Fable en barres animées, plus une sparkline de conso par heure.">
</p>

> L'interface de l'app est en **anglais**. Port **Windows** : [`windows/`](windows/README.md).

## Utilisation

- **L'app vit dans `/Applications/Conso Claude.app`** (aucune demande d'accès macOS).
- Clic gauche sur ✳ → le popover. Clic droit → options (Refresh, Test the plane,
  Start with macOS, Quit).
- Sémantique inversée (on affiche le restant) : le % passe **orange ≤ 50 %**,
  **corail ≤ 25 %** — corail = il reste peu, tuile à sec à 0 %. L'avion passe aux
  seuils 50/75/90 % de conso, une fois par session/semaine, sur l'écran où est la souris.

## Développement

Sources dans ce dossier : `main.swift` (app), `Banner.swift` (dessin avion +
banderole, partagé avec l'outil d'aperçu du scratchpad), `phrases.json`
(pool de phrases, embarqué au build — override possible dans
`~/Library/Application Support/Conso Claude/phrases.json`).

```bash
./build.sh              # build seulement (binaire universel arm64 + x86_64)
./build.sh --install    # build + installe dans /Applications + relance
./build.sh --zip        # build + crée "Conso Claude.zip" à partager
```

## Distribuer à des collègues

1. `./build.sh --zip` → envoyer **Conso Claude.zip**.
2. Côté collègue :
   - **Prérequis : un abonnement Claude Pro/Max.** Pas besoin de Claude Code ni
     du Terminal — l'app sait se connecter toute seule.
   - Dézipper, glisser `Conso Claude.app` dans `/Applications`.
   - Premier lancement : l'app n'est pas notarisée → macOS la bloque (« logiciel
     malveillant »). Cliquer **« Terminer »** (pas « Placer dans la corbeille »),
     puis Réglages Système → Confidentialité et sécurité → tout en bas,
     **« Ouvrir quand même »**. Une seule fois. (Le clic droit → Ouvrir ne
     suffit plus depuis macOS 15. Alternative terminal :
     `xattr -d com.apple.quarantine "/Applications/Conso Claude.app"`.)
   - Cliquer sur l'icône ✳ → **Sign in to Claude** : le navigateur s'ouvre, on
     autorise, c'est fini — le token est écrit dans le trousseau tout seul. (Si
     Claude Code est déjà connecté, l'app réutilise son token, rien à faire.)
3. Pour une diffusion large sans friction : compte Apple Developer (99 $/an)
   + `codesign` Developer ID + notarisation. Pas nécessaire entre collègues.

Binaire universel : tourne sur Apple Silicon et Intel. macOS 15 minimum.

## Comment ça marche

- Token OAuth de Claude Code lu dans le trousseau macOS
  (`security find-generic-password -s "Claude Code-credentials"`).
- Interroge `https://api.anthropic.com/api/oauth/usage` — le même endpoint que
  la page « Limites d'utilisation ». Chiffres exacts, pas une estimation.
- Sobre avec l'API : poll 10 min, re-fetch à l'ouverture seulement si > 5 min,
  backoff silencieux sur 429 (les données en cache restent affichées, ⚠ à côté
  de l'heure).
- Historique local (UserDefaults, 3 jours) pour la sparkline et la prédiction.
- Zéro dépendance, aucun secret stocké.

## Sécurité & confidentialité

- Le token n'est **jamais écrit sur disque ni loggé** : lu du trousseau au moment
  de la requête, gardé en mémoire, envoyé uniquement à `api.anthropic.com`
  (HTTPS, URL codée en dur, session réseau éphémère → zéro cache disque).
- Appel du trousseau par chemin absolu (`/usr/bin/security`) — pas de
  détournement de PATH possible.
- Aucune télémétrie, aucun serveur local, aucune dépendance tierce.
- Seules données persistées (UserDefaults) : pourcentages d'usage horodatés
  (sparkline, 3 jours glissants) et les derniers messages affichés. Rien de
  sensible.
- Le popover échappe toute donnée externe avant affichage (anti-injection HTML).
- La fenêtre de la banderole ignore la souris et ne capte aucune saisie.

## Si `✳ !` ou « Not signed in »

Cliquer sur l'icône ✳ → **Sign in to Claude** (le navigateur s'ouvre, on autorise).
Si le token existait déjà, un simple clic droit → Refresh suffit. Astuce : maintenir
**⌥** sur le menu affiche un repli « coller le code » au cas où le navigateur ne
revienne pas tout seul.
