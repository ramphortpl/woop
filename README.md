# Woop — ton WHOOP 5.0, sans abonnement

Application iOS (en français) qui se connecte **directement en Bluetooth** à un bracelet
**WHOOP 5.0 / MG** (et 4.0), récupère son historique et calcule **sur l'iPhone** le sommeil,
la récupération et l'effort, avec une interface calquée sur l'app WHOOP.

Aucun compte, aucun cloud : tout reste sur ton téléphone.

## Télécharger l'IPA — version 1.2.0

**➜ https://github.com/ramphortpl/woop/releases/download/v1.2.0/Woop.ipa**

Toutes les versions : [page des releases](https://github.com/ramphortpl/woop/releases).
Chaque modification du code reconstruit aussi l'application (GitHub Actions, macOS) ; la toute
dernière compilation est toujours ici :
https://github.com/ramphortpl/woop/releases/download/ipa-latest/Woop.ipa

L'IPA n'est pas signée : ouvre le lien depuis ton iPhone ou colle-le dans ton signer
(ESign, Feather, Scarlet, Sideloadly, AltStore…), signe-la puis installe-la.

## Nouveautés de la 1.2 — des chiffres plus justes

Toute la chaîne de calcul a été reprise en **combinant ce que noop et OpenStrap font de mieux**, et
calée sur de vrais chiffres WHOOP.

- **Sommeil** — nouvelle détection : immobilité du poignet confirmée par la fréquence cardiaque,
  l'état « endormi » du bracelet ne servant plus qu'à confirmer et à couper une grasse matinée.
  Une nuit n'est **plus coupée en deux** par un réveil de 20–30 min (défaut de la 1.1), les trous
  d'enregistrement ne comptent ni comme sommeil ni comme éveil, un garde-fou écarte l'immobilité
  éveillée (film du soir, bureau le matin : cœur au-dessus du niveau de sommeil), les bords de la
  nuit sont calés à la minute près et les siestes ont leur propre détection.
  Bouton **Corriger les heures de sommeil** si la détection se trompe (comme « Modifier » sur WHOOP).
- **Score de sommeil** comme WHOOP aujourd'hui : heures par rapport aux besoins, régularité,
  efficacité et stress pendant le sommeil (une vraie nuit WHOOP à 70 % / 54 % / 97 % / 0 % donne
  bien 76 %). Dette de sommeil : 55 % du manque reporté sur la nuit suivante.
- **VFC** — la 1.1 ne gardait que le sommeil profond de fin de nuit ; or les comparaisons de noop
  avec de vraies nuits WHOOP montrent que cette fenêtre lit trop haut. La 1.2 prend la médiane des
  fenêtres de 5 minutes de toute la nuit, avec un nettoyage plus strict : aucun écart n'est calculé
  à travers un battement manquant ou rejeté (ce défaut gonfle la VFC de 50 à 100 % sur WHOOP 5.0 /
  MG d'après les mesures d'OpenStrap). **FC au repos** : plus basse demi-heure de la nuit.
- **Effort** — nouvelle échelle logarithmique, vérifiée sur une vraie journée WHOOP (vélo 12,6 +
  randonnée 4,1 → journée 12,8) : une journée ne grimpe presque plus après une grosse séance, et une
  journée calme tourne autour de 5–7. **Zones de FC** sur la réserve cardiaque, comme WHOOP.
- **Calibrage sur TES données WHOOP** (*Plus › Importer depuis WHOOP*) : à partir de ton export, Woop
  apprend comment WHOOP calcule *ta* récupération, ton score et ton besoin de sommeil, ta dette, ton
  échelle d'effort, tes calories et ta répartition habituelle des phases ; chaque réglage n'est gardé
  que s'il prédit mieux tes chiffres WHOOP que le réglage par défaut. Les nuits mesurées à la fois par
  WHOOP et par Woop servent à aligner la VFC et la FC au repos.
- **Récupération des données** — la synchro ne tourne plus en boucle quand le bracelet ne répond
  pas (pause croissante), transfert toutes les 5 minutes app ouverte, nouvelle carte **Qualité des
  données** (heures réellement reçues du bracelet chaque jour) et avertissement firmware (voir
  ci-dessous).

> **Firmware 50.43 et suivants (WHOOP 5.0 / MG).** Des bracelets mis à jour ne livrent leur
> historique qu'après que l'app WHOOP officielle y a déposé son jeton d'abonnement signé (valable
> environ 45 jours). Aucune app tierce ne peut créer ce jeton. Si Woop est connecté mais ne reçoit
> plus rien : ouvre l'app WHOOP une fois, laisse-la se connecter au bracelet, puis resynchronise.
> C'est aussi l'app officielle qui installe les mises à jour de firmware. En attendant, l'option
> *Fréquence cardiaque en continu* (Plus › Mon bracelet) laisse Woop enregistrer le cœur en direct
> tant qu'il est connecté : sommeil, VFC et effort restent calculables, sans mouvement ni température.

## Nouveautés de la 1.1

- **Affichage refait au millimètre sur l'app WHOOP** : tailles, espacements et couleurs mesurés sur
  des captures de l'app officielle ; titres en capitales fines et espacées, chiffres de type DIN,
  texte géométrique (polices libres Montserrat, Figtree et Barlow), plus d'écriture trop épaisse.
- **Sommeil** comme sur WHOOP : grand anneau « Votre sommeil » (et pages heures / sommeil
  réparateur), analyse *Heures par rapport aux besoins*, *Régularité*, *Efficacité*, *Stress élevé
  pendant le sommeil* avec les barres Insuffisant / Suffisant / Optimal, puis *Sommeil des dernières
  nuits* : fréquence cardiaque pendant la nuit (repères coucher / réveil), phases Réveil, Léger,
  SOL (profond), SP avec ta **plage habituelle** en pointillés, sommeil réparateur. Touche une phase
  pour la voir sur le graphique. Bouton **Modifier** pour choisir les statistiques affichées.
- **Récupération** et **Effort** sur le même modèle, avec l'effort optimal du jour sur l'anneau et
  la courbe de fréquence cardiaque de la journée (activités et sommeil surlignés).
- **Commencer l'activité** comme sur WHOOP : carte plein écran, **BPM en direct en grand** dans le
  cercle bleu (« Déconnecté » si le bracelet ne l'est pas), *Suivi d'itinéraire* GPS, *Objectif
  d'effort*, puis pendant l'activité : effort, durée, distance, calories, FC moyenne en direct.
  Le parcours est enregistré avec l'activité.
- **Détail d'une activité** : FC minute par minute colorée par zone, zones, parcours sur la carte.
- **Plus fluide** : le rythme cardiaque en direct ne redessine plus tout l'écran chaque seconde,
  onglets gardés en mémoire (changement instantané), graphiques dessinés en une passe, retours
  haptiques légers.

## Connecter le bracelet

1. Ouvre Woop, remplis ton profil (âge, sexe, taille, poids : utilisés pour la FC max et les calories).
2. **Rechercher mon bracelet** → choisis ton WHOOP → **Connecter**. Accepte la demande d'appairage si iOS l'affiche.
3. Si le bracelet n'apparaît pas : tape plusieurs fois sur le capteur jusqu'à ce que les LED clignotent
   en bleu (mode appairage).
4. Si l'app WHOOP officielle est installée sur le même iPhone, la connexion peut être partagée (le lien
   Bluetooth chiffré appartient à l'iPhone). En cas de refus d'appairage : ferme l'app WHOOP, oublie le
   bracelet dans *Réglages › Bluetooth* et recommence.

La première synchronisation récupère tout l'historique stocké dans le bracelet (plusieurs jours) :
compte quelques minutes. Ensuite Woop resynchronise à l'ouverture, toutes les 5 minutes tant que l'app
est ouverte et toutes les 15 minutes sinon. La **récupération** apparaît après 4 nuits de calibrage,
comme sur WHOOP. *Plus › Mon bracelet › Qualité des données* montre combien d'heures le bracelet a
réellement livrées chaque jour : un jour avec des trous est noté sur ce qui est arrivé.

### Récupérer ton historique WHOOP (recommandé)

Dans l'app WHOOP, demande l'export de tes données (profil › Paramètres › Exporter les données) :
WHOOP t'envoie un e-mail avec un fichier `.zip`. Puis, au choix (*Plus › Importer depuis WHOOP*) :

- **Choisir le fichier .zip** : touche simplement le fichier, l'import démarre tout de suite
  (pas besoin du bouton « Ouvrir ») ;
- **Choisir le dossier décompressé** si Fichiers a déjà décompressé le `.zip` (entre dans le
  dossier puis « Ouvrir ») ;
- **Partager › Woop** depuis Mail, Safari ou Fichiers ;
- **Coller le lien** du bouton de téléchargement de l'e-mail ;
- ou dépose le `.zip` dans *Fichiers › Sur mon iPhone › Woop* : il est importé à la prochaine
  ouverture puis rangé dans « Importés ».

Les jours passés affichent alors **exactement les scores WHOOP** (récupération, effort, sommeil,
entraînements) et tes moyennes de référence sont calibrées immédiatement, sans attendre 4 nuits.
Woop en tire aussi son **calibrage personnel** (voir les nouveautés de la 1.2) : plus l'export couvre
de nuits, mieux les jours suivants collent à ce que WHOOP aurait affiché. Réimporte un export de
temps en temps : les nuits mesurées par les deux servent à aligner la VFC et la FC au repos.
Les exports en français et en anglais sont reconnus, même réenregistrés par Numbers ou Excel.

### Notifications (comme WHOOP)

*Plus › Notifications* : activité détectée (sport, horaires, effort, calories, avec **Confirmer** /
**Changer de sport**), activité enregistrée en direct, récupération du matin, sommeil analysé,
Moniteur de santé, effort optimal atteint ou dépassé, rappel du coucher, batterie du bracelet,
rappel de synchronisation et bilan de la semaine. Chacune s'active séparément ; un bouton envoie
une notification test.

iOS met Woop en veille : une activité est annoncée à la synchronisation suivante (ouverture de
l'app ou réveil par iOS). Pour être prévenu quelques minutes après la fin de l'activité, active
*Connexion continue au bracelet* (un peu plus de batterie du bracelet), et ne ferme pas Woop
depuis le sélecteur d'apps.

### Arrière-plan

iOS met l'app en veille : Woop resynchronise quand tu l'ouvres, quand iOS lui accorde un rafraîchissement
en arrière-plan, et le bracelet garde tout en mémoire en attendant. L'option *Fréquence cardiaque en
continu* (Plus › Mon bracelet) garde le flux en direct même app fermée, au prix de la batterie du bracelet.

Pas encore de bracelet sous la main ? *Plus › Mode démo* affiche l'interface avec des données simulées
(jamais mélangées à tes vraies données).

## Ce que fait l'app

| Écran | Contenu |
|---|---|
| **Accueil** | Anneaux Sommeil / Récupération / Effort, sélecteur de jour, série 🔥, batterie du bracelet, *Perspectives quotidiennes*, *Activités du jour* (sommeil, siestes, entraînements), *Sommeil de ce soir* (heure de coucher recommandée, alarme), *Mon tableau de bord* |
| **Personnaliser le tableau de bord** | Les 25 indicateurs de WHOOP (VFC, FC au repos, pas, zones de FC hebdo, VO₂ max, calories, effort et récupération, poids, temps de musculation, dette/efficacité/régularité du sommeil, fréquence respiratoire, sommeil réparateur…), réorganisables |
| **Sommeil** | Anneau « Votre sommeil », analyse Insuffisant / Suffisant / Optimal, FC pendant la nuit, phases (réveil, léger, SOL, SP) vs ta plage habituelle, sommeil réparateur, tendances 7 jours vs 30 jours, latence, perturbations, cycles, dette, correction manuelle des heures |
| **Récupération** | Score 0–100 % (vert / jaune / rouge), VFC, FC au repos, respiration et sommeil vs tes moyennes 30 j, tendances |
| **Effort** | Score 0–21 avec l'effort optimal du jour, FC de la journée, activités, zones de FC, calories, pas, tendances |
| **Commencer l'activité** | Carte, suivi d'itinéraire GPS, BPM en direct, objectif d'effort, effort / calories / distance en direct |
| **Activités** | Plus de 150 sports (raquette, collectifs, combat, nautiques, hiver, fitness…), recherche, récents, détection automatique, FC par zones et parcours |
| **Santé** | Moniteur de santé : FC au repos, VFC, respiration, SpO₂ (estimation), température cutanée vs ta norme |
| **Communauté** | Série, résumé de la semaine, records, défis (hors ligne) |
| **Plus** | Profil, bracelet (état, batterie, firmware, synchro, qualité des données, vibration, journal Bluetooth), import et calibrage WHOOP, réglages, données |
| **Coach (W)** | Réponses calculées localement à partir de tes données |

## Comment c'est construit

Woop combine les deux projets demandés, en prenant pour chaque brique la méthode la plus solide :

| Brique | Méthode retenue | Vient de |
|---|---|---|
| Connexion WHOOP 5.0, historique (« commit avant ACK »), enregistrements v18 | séquence 0003 → 0007 → 0005 → 0004, HELLO 0x91, contrat d'horloge | **OpenStrap** `edge` / `protocol` |
| Intervalles R-R en millisecondes sur WHOOP 5 | démontré sur 71 000 trames | **noop** |
| Détection des nuits | immobilité (gravité) + FC, gardes de jour / matin / hors poignet, raccord des fragments | **noop** `SleepStager`, repris par OpenStrap |
| Regroupement en une nuit, nuit principale, coupe de la grasse matinée, secondes non observées, siestes | groupes < 60–90 min, mi-sommeil habituel, état du bracelet en confirmation seulement | **OpenStrap** `segmentSleep`, `band_offset`, `nap` |
| Phases (léger / profond / paradoxal / éveil) | HMM + Viterbi, validé sur 44 personnes avec polysomnographie (κ 0,36) | **noop** `SleepStagerV2` |
| VFC | séries contiguës de battements propres, médiane des fenêtres de 5 min | **OpenStrap** `hrv_time` + **noop** `HRVAnalyzer` |
| FC au repos | plus basse demi-heure de la nuit | **OpenStrap** `nocturnal` |
| Effort 0–21 | zones sur la réserve cardiaque, échelle logarithmique D = 7201 | **noop** `StrainScorer` |
| Dette de sommeil | 55 % du manque reporté (ajusté sur 853 nuits WHOOP) | **noop** |
| Besoin de sommeil, heure de coucher | base + effort + dette − siestes | **OpenStrap** `coaching` |
| Récupération | z-scores VFC / FC repos / sommeil / respiration + logistique ; ou modèle ajusté sur ton export | **noop** `RecoveryScorer` + calibrage Woop |

Le cœur (protocole + calculs) est en Swift pur et testé avec de vraies trames WHOOP 5.0 capturées
(CRC vérifiés) : `swift test` à la racine.

```
Woop/Core/Protocol   trames, CRC, commandes, décodeurs, machine d'état de l'historique
Woop/Core/Analytics  sommeil, VFC, respiration, effort, récupération, besoin de sommeil
Woop/BLE             pilote CoreBluetooth
Woop/Store           base SQLite locale
Woop/UI              interface SwiftUI (français)
```

Construire soi-même (Mac) : `brew install xcodegen && xcodegen generate && open Woop.xcodeproj`.

## Limites honnêtes

- Les algorithmes de WHOOP sont privés et tournent sur ses serveurs. Woop utilise des méthodes publiées,
  calées sur de vrais chiffres WHOOP et, si tu importes ton export, ajustées sur les tiens : les valeurs
  sont proches, **pas garanties identiques**. Les durées de chaque phase de sommeil restent la partie la
  moins sûre (aucune montre ne les mesure vraiment ; WHOOP lui-même n'atteint que κ ≈ 0,37 face à la
  polysomnographie). Woop **n'est pas un dispositif médical**.
- Ce que le bracelet n'a pas livré ne peut pas être noté : si l'app WHOOP officielle vide l'historique
  pendant que Woop est fermé, ces heures manquent (carte *Qualité des données*).
- L'oxygène sanguin est une estimation non calibrée issue du bracelet.
- iOS limite l'exécution en arrière-plan : la synchronisation est la plus fiable quand l'app est ouverte.
- Application indépendante, **non affiliée à WHOOP, Inc.** Usage personnel, non commercial.

Licences : voir [LICENSE.md](LICENSE.md).
