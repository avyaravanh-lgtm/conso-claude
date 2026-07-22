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

## Distribuer (par les sources)

Cette app est un **compagnon de Claude Code** : elle lit le token OAuth que
Claude Code range dans le trousseau et affiche ta conso. Donc le prérequis
côté utilisateur, c'est **avoir Claude Code installé et connecté** (`claude`,
puis `/login`) — ça met un token qui marche dans le trousseau, que l'app lit.
Plus un abonnement **Pro/Max**.

On distribue **le code source**, pas un `.zip` : une app **compilée en local
n'est jamais mise en quarantaine** → aucun blocage Gatekeeper, aucune
notarisation, aucun « Ouvrir quand même ».

```bash
xcode-select --install    # une fois, si les Command Line Tools manquent
git clone https://github.com/avyaravanh-lgtm/conso-claude.git
cd conso-claude
./build.sh --install      # binaire universel (Apple Silicon + Intel) → /Applications
```

Binaire universel : Apple Silicon et Intel, macOS 15 minimum.

> **Pas de Claude Code ?** Le menu a un bouton « Sign in to Claude » qui lance
> l'OAuth lui-même, mais l'étape d'autorisation finale peut échouer sur
> certains comptes/machines — et ça, c'est côté Anthropic, hors de notre
> contrôle. Le chemin fiable : avoir Claude Code connecté, l'app fait le reste.

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

Vérifie que **Claude Code est connecté sur ce Mac** (`claude`, puis `/login`) :
ça écrit le token dans le trousseau, puis clic droit sur ✳ → **Refresh**. Le
bouton « Sign in to Claude » du menu existe aussi, mais le chemin fiable reste
le token de Claude Code.
