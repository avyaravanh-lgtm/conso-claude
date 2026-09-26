# Changelog

All notable changes to Conso Claude are documented here.

## 1.5.14 — 2026-09-26

### Ménage visuel du menu et du popover
Passe de finition UI/UX, une fois l'app stabilisée.

**Menu (clic droit)** — refonte concise et groupée :
- Groupes clairs : *Refresh* · *compte/jeton* · *extras* · *quitter*.
- Ligne d'état du jeton non cliquable (« Signed in — Conso's own token » / « Reading Claude
  Code's token »), puis les actions, resserrées et à cadre positif : « Sign in again… » et
  « Use Claude Code's token instead » (au lieu de « Remove Conso's token… »).
- « How to sign in… » retiré (redondant avec les actions), emoji ✈️ retiré, et « Start with
  macOS » → **« Open at Login »** (formulation standard macOS).

**Popover** :
- **Barres plates et nettes** — la lueur (box-shadow) « gamer » est retirée ; le léger dégradé
  suffit. Un widget de barre de menus reste calme.
- **Footer épuré** : le bouton « test avion » quitte le popover (il reste dans le menu). Ne
  restent que *rafraîchir* et la version.
- **Ligne session lisible** : la prédiction (« empty ~HH:MM ») OU le reset s'affiche, plus les
  deux — ils se chevauchaient et tronquaient « 5-hour session ». Le reset complet reste dans
  l'infobulle. Rendu vérifié par capture (WKWebView).

## 1.5.13 — 2026-09-26

### L'avion ne passe plus par-dessus une app en plein écran (jeu, vidéo…)
Demande de Monsieur : pas d'avion-banderole quand on est en plein écran. Avant de faire voler
l'avion, Conso vérifie si une app couvre tout l'écran ; si oui, l'avion est **sauté** (la conso
reste consultable dans le popover). Détection **sans permission** : on ne lit que le calque et
les bornes des fenêtres (pas les titres, qui exigeraient l'autorisation d'enregistrement
d'écran) — une fenêtre de calque 0 qui couvre tout l'écran = plein écran.

Aussi : la fenêtre de login prévient désormais que la connexion passe brièvement par Claude
Code (macOS peut demander une permission la 1re fois) et qu'on n'a à le faire qu'≈ une fois par
an — de préférence pas en pleine partie.

## 1.5.12 — 2026-09-26

### Login via setup-token : capture du jeton fiabilisée (PTY)
En 1.5.11, le flux OAuth réussissait (écran de succès) mais Conso ne **capturait pas** le
jeton : lancé sans terminal, `claude setup-token` se met en mode silencieux (1 octet écrit)
et, via un pipe, la lecture restait bloquée (descripteur hérité par le navigateur, jamais
d'EOF). L'entrée Trousseau de Conso restait vide et le popover bloqué sur « Opening Claude in
your browser… ».

Correctif : Conso lance le CLI dans un **vrai PTY** (pseudo-terminal). `setup-token` se croit
alors dans un terminal, imprime tout (vérifié : « Welcome… », « Opening browser… », puis le
jeton) en ligne, et Conso **lit le côté maître** au fur et à mesure — dès que le jeton
`sk-ant-oat…` apparaît, il le capture, le range dans sa propre entrée, et repart. Les codes
ANSI du CLI sont retirés avant extraction. Filet de 5 min si personne n'autorise.

## 1.5.11 — 2026-09-26

### Login indépendant : on délègue au vrai CLI (`claude setup-token`)
Constat après enquête : l'URL d'autorisation que Conso génère est **identique caractère pour
caractère** à celle du vrai CLI (vérifié en capturant l'URL de `claude setup-token` et en
comparant). Pourtant claude.ai **accepte** le flux du CLI et **refuse** celui de Conso après
« Autoriser » (« Invalid request format ») — une différence côté serveur qu'on ne peut pas
reproduire depuis l'app, quelle que soit la fidélité de la requête.

Donc au lieu de réimplémenter l'OAuth, **Conso délègue au flux officiel** : « Sign in to
Conso » lance `claude setup-token` (qui, lui, marche), l'utilisateur clique **Autoriser** une
fois dans le navigateur, et Conso **capture le jeton longue durée** que le CLI imprime,
directement dans sa propre entrée Trousseau. **Zéro copier-coller**, flux navigateur officiel,
jeton longue durée (donc plus de dépendance à Claude Code ouvert, plus de refresh).

Vérifié : lancé comme sous-processus par Conso, `setup-token` ouvre bien le navigateur et
n'imprime le jeton qu'après autorisation. Le jeton `setup-token` est « inference-only » et ne
touche jamais l'entrée Trousseau de Claude Code (constaté : elle reste inchangée).

## 1.5.10 — 2026-09-25

### Login indépendant : URL copiée à l'identique du vrai CLI (loopback + user:inference)
Après plusieurs « Invalid request format » (au chargement puis, en v1.5.8/1.5.9, APRÈS
« Autoriser »), j'ai **capturé l'URL exacte** que génère `claude setup-token` — le flux
« jeton long pour abonnement », qui est précisément l'usage de Conso — en interceptant
l'ouverture du navigateur, sans compléter le login. Deux écarts corrigés :
- **Loopback `http://localhost:<port>/callback`**, pas le callback hébergé
  `platform.claude.com/oauth/code/callback` (ce dernier est réservé aux comptes Console ;
  d'où l'échec APRÈS Autoriser sur un compte Max). Le navigateur revient tout seul, **fini
  le copier-coller**.
- **Scope = `user:inference` SEUL**, au lieu de mes listes à 5-6 scopes. Un seul scope =
  aucun espace à encoder → notre URL est identique caractère pour caractère à celle du CLI.

La fenêtre de confirmation, jugée trop intimidante, est raccourcie.

## 1.5.9 — 2026-09-25

### Login indépendant : scope `org:create_api_key` retiré (échec au callback)
En v1.5.8, la page de consentement Claude s'affichait bien (endpoints corrects), mais après
« Autoriser » le **callback** échouait sur « Invalid request format ». Cause trouvée en
décodant le vrai CLI `claude` **et** en relisant le jeton de Claude Code : le scope
**`org:create_api_key`** est un scope **Console/organisation** qu'un compte perso **Max** ne
possède pas. Il est toléré à l'affichage du consentement (qui ne le liste même pas) mais fait
échouer l'étape de callback. Retiré. Scopes désormais alignés sur ce qu'un login claude.ai/Max
accorde réellement : `user:inference user:profile user:sessions:claude_code user:mcp_servers
user:file_upload`.

Endpoints confirmés identiques à ceux du CLI `claude` (bundle) : autorisation
`claude.com/cai/oauth/authorize` (voie Max), callback hébergé
`platform.claude.com/oauth/code/callback`, token `platform.claude.com/v1/oauth/token`.

## 1.5.8 — 2026-09-25

### Icône de barre de menus remise ; login indépendant corrigé (voie du CLI)
1. **Marque de la barre de menus remise à l'ancienne** (`✳︎` devant le %) — à la demande
   de Monsieur. (L'icône de l'app / Dock n'avait jamais changé.)
2. **Login indépendant — « Invalid request format » corrigé.** Le premier essai (v1.5.7)
   ouvrait `claude.com/cai/oauth/authorize` avec un **redirect loopback `localhost`** que le
   client OAuth n'accepte pas → rejet. La config du vrai CLI `claude` (relevée dans son
   bundle) le confirme : deux URL d'autorisation (`CONSOLE_AUTHORIZE_URL` pour l'API,
   `CLAUDE_AI_AUTHORIZE_URL` pour l'abonnement Max), token sur `platform.claude.com`, et
   **callback hébergé** `platform.claude.com/oauth/code/callback`. On aligne dessus :
   - autorisation par la voie **claude.ai / Max** (`claude.com/cai/oauth/authorize`) ;
   - **callback hébergé + collage du code** (comme `claude` en CLI), fini le loopback ;
   - échange du token sur `platform.claude.com/v1/oauth/token`.
3. **Bug corrigé** : après un login échoué sans retour navigateur, `loggingIn` restait bloqué
   à `true` — un reclic sur « Sign in » ne faisait plus rien. `startLogin` réinitialise
   maintenant tout login en cours avant d'en relancer un.

L'invariant de sûreté est inchangé (écriture Trousseau verrouillée sur l'entrée de Conso ;
repli lecture-seule sur Claude Code). Reste à confirmer en réel que l'autorisation aboutit.

## 1.5.7 — 2026-09-25

### Jeton indépendant : Conso peut avoir SON propre jeton (fini le « Paused »)
**Le besoin.** Conso lit le jeton de Claude Code. Ce jeton expire ≈ chaque soir et, si on
n'utilise pas Claude Code sur cette machine, Conso reste « Paused » faute de pouvoir le
renouveler (elle est lectrice seule — voir 1.5.0, et l'incident du 14/09 où renouveler le
jeton PARTAGÉ tuait les sessions).

**La solution — une entrée Trousseau SÉPARÉE.** Conso peut maintenant faire son PROPRE
login OAuth (menu clic droit → « Sign in to Conso (independent token) »). Elle obtient
alors son propre jeton, rangé dans **sa** propre entrée (`Conso Claude-credentials`),
qu'elle rafraîchit elle-même — sans jamais toucher celle de Claude Code.

**Sûr par construction :**
- **Un seul chemin d'écriture** (`writeConsoCreds`), avec le service et le compte EN DUR
  sur l'entrée de Conso. Aucun appelant ne peut lui faire écrire l'entrée de Claude Code.
  L'entrée `Claude Code-credentials` n'est plus utilisée qu'en **lecture** (repli). Le
  partage qui a causé le 14/09 est structurellement impossible.
- **Jamais pire que le repli.** Si le jeton propre de Conso fait défaut (réseau, refresh
  échoué, jeton refusé), Conso **retombe** sur le jeton de Claude Code (ou attend) —
  jamais elle n'efface les chiffres. Le jeton indépendant ne peut qu'AJOUTER de la vivacité.
- **Réversible en un clic.** Menu → « Remove Conso's token (back to Claude Code) » supprime
  l'entrée de Conso et revient au comportement lecture seule, sans trace.
- **Opt-in.** Tant qu'on n'a pas fait ce login, le comportement est identique à avant.

Le menu indique la source courante (« Token — Conso's own ✓ » ou « borrowed from Claude
Code »). Voie de login : serveur loopback local (zéro copier-coller), repli collage manuel.

> ⚠️ Un point ne peut se valider qu'en conditions réelles : qu'une 3ᵉ autorisation OAuth
> coexiste avec celles du mini et du MacBook sans invalider la session de Claude Code
> (politique côté serveur). À tester ensemble, avec le retrait réversible comme filet.

## 1.5.6 — 2026-09-25

### Retours de Monsieur sur l'avion (v1.5.5) — trois défauts corrigés
1. **Les avions « tournaient en boucle ».** Le test tirait les **trois** familles à la
   suite, et chaque reclic empilait une nouvelle file (les vols sont sérialisés) → une
   rafale sans fin. Désormais **un seul avion par clic**, qui **change de famille** à
   chaque fois (session → tous modèles → Fable → …). Reclique pour voir la suivante.
2. **Libellés en français dans une app anglaise.** Retour à l'anglais, cohérent avec le
   reste : `SESSION · 5H`, `WEEKLY · ALL MODELS`, `WEEKLY · FABLE`, et `left` (au lieu de
   « restant »).
3. **Le « vieux emoji » dans la barre de menus.** Le glyphe `✳︎` (U+2733 + VS15) posé
   devant le pourcentage ressortait comme un vieil emoji. Remplacé par une **vraie icône
   template** (SF Symbol `asterisk`), qui se teinte proprement selon la barre (clair /
   sombre / survol). Plus aucun préfixe glyphe dans le texte — juste l'icône et le
   pourcentage.

## 1.5.5 — 2026-09-24

### L'avion dit maintenant DE QUELLE conso il parle — visuellement
**Le symptôme.** « On reçoit des avions pour les trois (session, tous modèles, Fable) avec
des valeurs différentes, et on ne comprend pas de quoi ils parlent. » L'ancienne banderole
ne se distinguait que par une ligne de texte en petites capitales.

**Le correctif — reconnaître la famille SANS lire.** Chaque avion porte désormais trois
repères visuels, en plus du texte :
- **Une icône par famille** : ⏱ horloge pour la **session (5 h)**, ▮▮▮ barres croissantes
  pour **tous modèles · semaine**, ◆ losange pour un **modèle nommé · semaine** (Fable…).
- **Une couleur d'identité par famille** (bleu / violet / vert-sarcelle), portée par l'icône,
  le libellé et le liseré de la carte — **indépendante** de la couleur d'urgence du grand
  nombre (corail / orange / rouge). L'une dit *laquelle*, l'autre *combien*.
- **Une jauge** à côté du nombre : le remplissage = ce qu'il reste, d'un coup d'œil.

Le libellé passe en français et garde le nom du modèle pour les quotas par modèle
(« FABLE · SEMAINE »). Le **test d'avion** (clic droit → « Test the plane ✈️ ») fait
maintenant défiler les **trois** familles à la suite, pour vérifier la distinction.

## 1.5.4 — 2026-09-24

### Le bas du popover coupé, encore — cette fois en état « Paused »
**Le symptôme.** En état d'attente (jeton expiré), le message « Paused — refreshes next
time you use Claude Code. » passe sur **deux lignes**, la fenêtre reste trop courte et le
footer (bouton ↻ refresh, ✈︎, version) se fait rogner. « Pas de refresh, la fenêtre n'est
pas bien dimensionnée. »

**La cause — la racine, pas le énième symptôme.** La hauteur de la fenêtre était **devinée
à la main** dans `popoverSize()` : 38 px par ligne, +22 px si message, +52 px si login…
Chaque cas qui ne rentrait pas dans ces suppositions coupait le bas — la prédiction
`empty ~HH:MM` en 1.5.3, le message « Paused » sur deux lignes ici, et le prochain cas
qu'on n'a pas prévu. On réparait un symptôme à la fois.

**Le correctif — mesurer au lieu de deviner.** Le popover mesure désormais sa **hauteur de
contenu réelle** (`document.body.scrollHeight`, après mise en page) et la renvoie à l'app,
qui redimensionne la fenêtre pile dessus (`applyMeasuredHeight`). `popoverSize()` ne sert
plus que de secours pour la toute première ouverture, avant la première mesure. Résultat :
**toute cette classe de bugs de « bas coupé » disparaît d'un coup**, quel que soit le
contenu (message court ou long, prédiction, spark, bloc login…).

*Note : ceci corrige l'AFFICHAGE en état « Paused ». L'état « Paused » lui-même reste le
comportement voulu et sûr d'une app lectrice seule (voir 1.5.0) — le jeton de Claude Code
expire ≈ chaque soir et Conso attend qu'il le renouvelle, sans jamais y toucher.*

## 1.5.3 — 2026-09-22

### Le haut du popover se casse, le bas (boutons ↻ ✈︎, version) disparaît
**Le symptôme.** « On voit plus rien en bas, les boutons refresh ont disparu. » Et sur la
première ligne, le libellé tronqué (« 5-hour sess… »), un `47` orphelin sous la ligne, et
la prédiction qui déborde.

**La cause — une seule, pour les deux symptômes.** La hauteur de la fenêtre est **calculée
à l'avance** dans `popoverSize()`, sur l'hypothèse **d'une ligne = 38 px** ; le HTML est en
`body { overflow:hidden }`. Cet invariant tenait tant qu'aucune ligne ne passait sur deux
rangées. Or la ligne « 5-hour session » reçoit en plus la **prédiction** `empty ~HH:MM`
(`sessionEta()`) : quand elle s'affiche **en même temps** que le compte à rebours de reset
(`3 h 47`), l'ensemble libellé + prédiction + reset + `%` ne tient plus sur une rangée. Le
reset passe à la ligne (le `47` orphelin), la ligne fait ~52 px au lieu de 38, tout est
poussé de ~14 px vers le bas, et **le footer sort de la zone visible et se fait rogner**.

**Le correctif — garantir une seule rangée par ligne** (l'invariant sur lequel repose tout
le calcul de hauteur) :
- **`.reset { white-space:nowrap }`** — le compte à rebours ne se coupe plus jamais (fini le
  `47` orphelin, et c'est lui qui débordait la hauteur).
- **`.meta { flex-shrink:0 }`** — le bloc `prédiction · reset · %` garde toujours sa rangée
  entière ; c'est le libellé qui absorbe le manque de place.
- **`.label { min-width:0 }`** — sans lui, un flex item refuse de descendre sous la largeur
  de son contenu et l'`text-overflow:ellipsis` ne se déclenche jamais. Avec, le libellé se
  tronque proprement au lieu de pousser la meta hors cadre.

Aucune donnée n'était perdue : c'était un débordement de mise en page. Les trois barres, la
prédiction, le reset et le footer coexistent désormais sans se chevaucher ni se faire rogner.

## 1.5.2 — 2026-09-17

### « Session expired » en orange tous les soirs, alors que rien n'est cassé
**Le symptôme.** « Je tombe constamment sur *session à rafraîchir* alors que Claude Code
est ouvert. » Le popover affichait un bandeau **orange d'alerte** « Session expired » une
grande partie de chaque soirée et de chaque nuit.

**La cause — pas un bug, mais une alarme mal calibrée.** Le journal `oauth.log` est sans
équivoque : le jeton de Claude Code expire ≈ chaque soir (~17-18h) et **le reste jusqu'au
lendemain matin**, quand Monsieur se sert de Claude Code pour la première fois (reprises
constatées à 09h04, 10h22, 11h45). C'est le fonctionnement **normal** d'une app lectrice
seule (1.5.0) : elle ne renouvelle jamais le jeton — c'est Claude Code qui le fait, et
seulement à un vrai appel. Le problème n'est donc pas la logique (elle repart bien toute
seule), c'est qu'on **criait au feu** en orange chaque soir pour un état parfaitement
attendu et sans gravité.

**Le correctif — distinguer une attente d'une panne :**
- **Un état « en attente » à part, calme.** Le jeton expiré qui attend Claude Code n'est
  plus traité comme une erreur : il s'affiche en **gris discret**, pas en orange (réservé
  désormais aux vraies pannes — réseau, 429, HTTP inattendu). Les deux ne coexistent jamais.
- **Un texte honnête et sans stress.** « Paused — refreshes next time you use Claude Code. »
  Fini « Session expired », qui laissait croire à une déconnexion : la session Claude de
  Monsieur n'a rien perdu, c'est juste le jeton lu par Conso qui a fait son temps et
  repartira au prochain usage. Les derniers chiffres connus restent affichés (en cache),
  l'icône de la barre de menus ne change pas.

## 1.5.1 — 2026-09-16

### « Session expired » qui ne bougeait pas alors que Claude Code était ouvert
**Le symptôme.** Le matin, après une nuit sans activité, le popover affichait
« Session expired — open Claude Code to refresh. » et **restait bloqué** : Claude Code
était pourtant ouvert, et « j'ai beau refresh, ça ne prend pas ».

**La cause, pas un bug — la conséquence du bon design.** Depuis la 1.5.0, l'app est
**lectrice seule** du jeton de Claude Code (elle ne le renouvelle plus elle-même, c'est ce
qui cassait la session partagée). Or Claude Code ne renouvelle le jeton **qu'au moment d'un
vrai appel API**, pas juste parce qu'une fenêtre reste ouverte. Une fenêtre ouverte mais
oisive depuis avant l'expiration (typiquement toute la nuit) ne déclenche donc rien, et
l'app attend, à raison, un jeton frais qui n'arrive pas tant qu'on ne se sert pas de Claude
Code. Cliquer ↻ relisait le même jeton expiré → toujours le même message.

**Le correctif — dire la vérité, et repartir dès qu'on peut :**
- **Message honnête.** « Session expired — use Claude Code once and it refreshes on its
  own. » Fini le « open Claude Code » qui laissait croire qu'ouvrir suffit : ce qu'il faut,
  c'est *se servir* de Claude Code une fois (un message suffit), et Conso repart seul.
- **Reprise instantanée à l'ouverture du popover.** Quand l'app attend un jeton frais,
  ouvrir le popover (ou cliquer ↻) relit le Trousseau **immédiatement** au lieu d'attendre
  le poll d'une minute — dès que Claude Code a reposé un jeton neuf, l'affichage repart à
  l'instant où on regarde.

Aucun changement au principe lectrice-seule : l'app ne touche toujours jamais l'entrée
`Claude Code-credentials` du Trousseau.

## 1.5.0 — 2026-09-14

### Lectrice seule du jeton Claude Code — fini le partage de refresh token qui cassait la session
**Le bug de fond.** Depuis la v1.2, l'app ne se contentait pas de lire le Trousseau :
elle renouvelait elle-même le jeton OAuth (`grant_type=refresh_token`) et réécrivait
l'entrée `Claude Code-credentials`. Or ce **refresh token est à usage unique et tourne
à chaque échange**. L'app et chaque processus Claude Code s'en partageaient une copie ;
tôt ou tard l'un présentait un jeton déjà consommé, et la session mourait **pour tout le
monde** — `accessToken`/`refreshToken` vidés dans le Trousseau, Conductor et le CLI
`claude` déconnectés (« OAuth session expired and could not be refreshed »). Constaté le
14/09/2026 ; `oauth.log` montrait « refresh token → HTTP 200 » le matin puis « HTTP 400 »
en boucle dès 16:27.

**Le correctif — l'app redevient un simple compagnon, jamais un second client OAuth :**
- **Lecture seule du Trousseau.** Plus aucun `grant_type=refresh_token`, plus aucune
  écriture de l'entrée `Claude Code-credentials`. `readCreds()` n'extrait que
  l'`accessToken` et l'`expiresAt` — pas de compte, pas de blob complet, pas de
  refreshToken : réécrire est devenu **impossible par construction**. `refreshOAuthToken()`
  et `writeCreds()` sont supprimés.
- **Jeton expiré ou rejeté (401/403) → on attend Claude Code.** L'app garde les derniers
  chiffres connus en **« stale »**, affiche « Session expired — open Claude Code to
  refresh. », **pose un backoff franc (au plus une tentative réseau par minute)** et
  **relit le Trousseau une fois par minute**. Dès que Claude Code repose un jeton frais,
  l'app repart toute seule — sans jamais toucher au jeton.
- **Login intégré retiré.** L'app ne fait plus le flux OAuth (loopback + navigateur) :
  c'est ce flux qui expirait en « connexion invalide ». Le popover affiche désormais
  « Sign in with Claude Code — run `claude auth login`, then refresh », et le menu propose
  « How to sign in… ». Serveur loopback, PKCE, échange de code et endpoints de token
  supprimés.
- **`oauth.log` ne montre plus jamais « refresh token → »** (la ligne n'existe plus) et
  n'a, comme avant, jamais contenu de secret.

## 1.4.0 — 2026-07-22

### Login intégré refait sur le flux `/login` (loopback) + doc distribution honnête
Enquête menée jusqu'au bout en extrayant la config OAuth de prod du binaire
`claude-code` v2.1.216 (`client_id 9d1c250a…`, `claude.com/cai/oauth/authorize`,
redirect loopback `http://localhost:<port>/callback`, scopes « Khi »). **Verdict :
la requête de l'app est identique à celle de l'outil officiel `claude`.** Le
« Invalid request format » survient **après le clic « Autoriser »**, côté serveur
Anthropic — reproduit avec une URL d'autorisation officielle, page de consentement
affichée puis refus à l'approbation. **Ce n'est donc pas réparable dans l'app** : le
login neuf dépend d'une étape d'autorisation qu'on ne contrôle pas.

Ce que cette version change quand même :
- **Login intégré aligné sur le vrai `/login`** : serveur loopback local
  (127.0.0.1, port éphémère, interface loopback uniquement) → le navigateur revient
  tout seul, plus de copier-coller ; scopes complets « Khi » ; `redirect_uri`
  identique entre autorisation et échange ; repli manuel + timeout 180 s.
- **Chemin fiable assumé = lire le token Claude Code du trousseau.** Quiconque a
  Claude Code connecté n'a pas besoin du bouton « Sign in ».
- **README (FR/EN) refaits** : app positionnée en **compagnon de Claude Code**,
  distribution **par les sources** (`git clone` + `./build.sh` → app compilée en
  local, jamais mise en quarantaine, donc zéro Gatekeeper, zéro notarisation).

## 1.3.6 — 2026-07-21

### Coin haut-gauche du popover : fond opaque, fini le glint
- Le coin haut-gauche montrait une tache colorée (« moche ») : le Liquid Glass
  (NSGlassEffectView) — puis le matériau frosté (NSVisualEffectView) — laissaient
  **transparaître/refléter le fond derrière la fenêtre** et le concentraient en un
  glint de bord au coin (ex. un onglet vert derrière → coin verdâtre). Vérifié à
  l'écran sur fond vert pur.
- **Fix** : la carte du popover est désormais **opaque** (fond ivoire adaptatif
  clair/sombre peint par le HTML), coins arrondis en squircle continu + hairline
  discrète. Rendu net et identique sur **n'importe quel** fond, plus aucun glint.

## 1.3.5 — 2026-07-21

### Numéro de version visible + constat sur le login
- **Version affichée** dans l'app : en haut du menu clic droit (« Conso Claude
  1.3.5 ») et dans le pied du popover. Permet de vérifier d'un coup d'œil quelle
  build tourne.
- **Login OAuth — diagnostic** : l'échec « Invalid request format » après clic sur
  « Autoriser » n'est **pas** un bug de l'app. Vérifié en lançant l'outil officiel
  `claude setup-token` : il ouvre une URL byte-identique à celle de l'app et
  échoue **exactement pareil** au même moment. C'est un problème côté serveur
  d'autorisation (ou lié à un compte ayant déjà autorisé Claude Code). L'app lit
  toujours parfaitement le token existant ; le login intégré reste en place pour
  quand le flux d'Anthropic refonctionnera / sur une machine jamais autorisée.

## 1.3.4 — 2026-07-21

### LA vraie cause du bouton « Sign in » toujours affiché : un bug CSS
Depuis la 1.3, le bouton « Sign in to Claude » restait visible **en permanence**,
même avec un token valide et `needsLogin=false`. Toutes les corrections de logique
Swift précédentes étaient correctes mais **masquées** par ce bug :
- La règle `#login { display:block }` a une spécificité (id) supérieure à celle de
  l'attribut `[hidden]` du navigateur → `element.hidden = true` était **ignoré**,
  le bouton s'affichait toujours.
- Fix : `#login[hidden] { display:none }`.

Vérifié **à l'écran** (capture du popover) : `needsLogin=false` → bouton bien
masqué, popover propre (conso + graphe), coins arrondis corrects. La logique
`needsLogin` des versions 1.3.1→1.3.3 fonctionnait déjà ; il ne manquait que ça.

## 1.3.3 — 2026-07-21

### Plus de bouton « Sign in » fantôme quand un token existe
- **Bug corrigé** : un essai de login manuel raté (mauvais code collé, annulation)
  mettait `needsLogin=true` de façon collante — le gros bouton « Sign in » restait
  affiché **alors qu'un token Claude Code valide était présent et lu**. `needsLogin`
  est désormais re-dérivé à chaque refresh depuis l'état réel du token : bouton
  seulement s'il n'y a vraiment aucun token lisible.
- `loginFailed` ne force plus le bouton ; il relance un refresh qui rétablit l'état.
- **Garde-fou** : « Sign in » sur une machine qui a déjà un token (Claude Code
  connecté) demande maintenant confirmation — se reconnecter écraserait le token
  par un scope plus étroit. Sur une telle machine, l'app affiche la conso toute
  seule, aucune connexion n'est nécessaire.
- Effet de bord réglé : la hauteur du popover (et les « coins » de l'état sign-in)
  ne s'affichent plus par erreur sur une machine déjà connectée.

## 1.3.2 — 2026-07-21

### Login OAuth aligné à l'identique sur `claude setup-token`
Le 1.3.1 échouait encore (« Invalid request format »). J'ai capturé l'URL réelle
générée par `claude setup-token` et corrigé les trois derniers écarts :
- **Scope** : `user:inference` **seul** (j'envoyais 3 scopes → rejet).
- **Redirect** : `https://platform.claude.com/oauth/code/callback` (callback
  hébergé qui affiche le code), au lieu d'un serveur loopback local.
- **Encodage** : `redirect_uri` et `scope` sont maintenant percent-encodés
  (`%3A`, `%2F`) exactement comme le CLI ; URLComponents les laissait en clair.
- **Flux** = copier-coller (comme `setup-token`) : le navigateur affiche un code,
  on le colle dans l'app. Le serveur loopback (jamais accepté par le serveur) est
  supprimé, ainsi que la dépendance au framework Network.
- L'échange essaie les deux endpoints de token connus (api.anthropic.com puis
  platform.claude.com) par sécurité.

Vérif : l'URL d'autorisation produite est désormais **byte-identique** à celle de
`claude setup-token` (qui fonctionne), donc l'erreur « Invalid request format »
est éliminée. Le seul maillon non automatisable reste le clic « Autoriser » +
collage du code.

## 1.3.1 — 2026-07-21

### Correctif login OAuth (le 1.3 ne se connectait pas)
- **Mauvais endpoint d'autorisation.** Le 1.3 tapait `claude.ai/oauth/authorize`
  (→ HTTP 403 « Invalid request format »). Le login de Claude Code a migré sur
  **`claude.com/cai/oauth/authorize`** — corrigé. Valeurs relevées directement
  dans le binaire `claude-code` de prod (client_id, scopes, ordre des paramètres).
- **`code=true` manquant** dans le flux loopback : il est maintenant toujours
  envoyé, comme le fait le CLI.
- **Redirect en `localhost`** (et non `127.0.0.1`) — c'est la forme déclarée comme
  autorisée côté client OAuth ; le serveur local écoute désormais sur l'interface
  **loopback** (couvre IPv4 et IPv6, rien exposé au réseau).
- Vérifs : URL d'autorisation 307 (vs 403 avant), endpoint d'échange qui accepte
  le format (`invalid_grant` sur code bidon, pas `invalid_request`), PKCE conforme
  RFC 7636, capture loopback du `localhost` OK.

## 1.3 — 2026-07-21

### Login intégré — l'app est autonome
- Nouveau bouton **« Sign in to Claude »** dans le popover (et dans le menu clic
  droit). Plus besoin d'installer Claude Code ni de passer par le Terminal : l'app
  fait **le premier login OAuth elle-même** et écrit le token dans le Keychain.
- Flux **loopback local + PKCE** (comme le login de Claude Code) : le navigateur
  s'ouvre, on autorise, le retour est capté automatiquement — **zéro copier-coller**.
- **Repli copier-coller** accessible en maintenant **⌥** sur le menu (ou déclenché
  automatiquement si le serveur local ne peut pas démarrer) : la page affiche un
  code, on le colle dans l'app.
- Garde-fou **timeout 2 min** : plus de blocage en « attente d'autorisation » si
  l'onglet est fermé ou l'accès refusé.
- Messages remaniés : « Token not found → open Claude Code » devient
  « Not signed in » avec le bouton de connexion ; le 401 devient « Session expired
  — sign in again ».

## 1.2 — 2026-07-14

### Auto-refresh du token
- L'app **renouvelle le token OAuth elle-même** via le `refreshToken` du Keychain,
  sans dépendre de l'ouverture de Claude Code. Au réveil du Mac, la conso repart
  toute seule au lieu de rester bloquée sur « Token expired ».
- Refresh **proactif** quand le token est expiré (ou l'est dans la minute), et
  **réactif** en secours sur un 401, suivi d'un retry de l'appel usage.
- Le nouveau token (rotation du `refreshToken` incluse) est **réécrit dans le
  Keychain**, donc Claude Code reste en phase.
- Si le refresh échoue lui aussi, message clair : « reconnect Claude Code (/login) ».

## 1.1 — 2026-07-13

### Usage chart
- **Per-hour usage bars** instead of the old cumulative session curve. Each bar
  shows how much you actually burned during that hour (the derivative), so a
  calm hour and a heavy one read at a glance. Session resets no longer look like
  a misleading "hill".
- **24-hour window**, adaptive: it grows with the history available (no empty
  bars early on) and tops out at a full day.
- **Hour labels** under the bars (local time); the current hour sits on the right.
- **Scale floor at 20 %/h** — the rate that would drain a whole session in 5 h.
  Below it, the scale stays put so a quiet day looks quiet; above it, the chart
  goes back to adaptive so heavy days are never squashed. A `PEAK N%/H` label
  gives the exact figure.

### Accessibility & readability
- Boosted the smallest chart text (caption + hour labels) for contrast.
- Gauge labels nudged over the WCAG AA threshold (4.5:1).
- Honors macOS **"Increase contrast"** (`prefers-contrast`): every tier gets
  denser when the setting is on, quiet look by default.

### Look & feel
- **Liquid Glass** (macOS 26+): the panel now uses a native `NSGlassEffectView`.
  On older macOS it falls back cleanly to the previous rendering.
- The popover became a **borderless floating panel** (like Control Center):
  no anchor triangle, clean rounded corners, and it lets the desktop show
  through subtly behind the glass.
- Hairline separators between gauges / chart / buttons, softer button hovers.
- Removed the clock in the footer (a `⚠︎` still flags cached data).

## 1.0 — 2026-07-06

- First release: menu-bar monitor for Claude usage limits on macOS (session +
  weekly), with the paper-plane banner and local history.
