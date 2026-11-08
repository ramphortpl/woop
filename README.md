# Woop — ton WHOOP 5.0, sans abonnement

Application iOS (en français) qui se connecte **directement en Bluetooth** à un bracelet
**WHOOP 5.0 / MG** (et 4.0), récupère son historique et calcule **sur l'iPhone** le sommeil,
la récupération et l'effort, avec une interface calquée sur l'app WHOOP.

Aucun compte, aucun cloud : tout reste sur ton téléphone.

## Télécharger l'IPA — version 1.1.0

**➜ https://github.com/ramphortpl/woop/releases/download/v1.1.0/Woop.ipa**

Toutes les versions : [page des releases](https://github.com/ramphortpl/woop/releases).
Chaque modification du code reconstruit aussi l'application (GitHub Actions, macOS) ; la toute
dernière compilation est toujours ici :
https://github.com/ramphortpl/woop/releases/download/ipa-latest/Woop.ipa

L'IPA n'est pas signée : ouvre le lien depuis ton iPhone ou colle-le dans ton signer
(ESign, Feather, Scarlet, Sideloadly, AltStore…), signe-la puis installe-la.

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
compte quelques minutes. Ensuite Woop resynchronise à l'ouverture et toutes les 15 minutes quand il est
connecté. La **récupération** apparaît après 4 nuits de calibrage, comme sur WHOOP.

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
| **Sommeil** | Anneau « Votre sommeil », analyse Insuffisant / Suffisant / Optimal, FC pendant la nuit, phases (réveil, léger, SOL, SP) vs ta plage habituelle, sommeil réparateur, tendances 7 jours vs 30 jours, latence, perturbations, cycles, dette |
| **Récupération** | Score 0–100 % (vert / jaune / rouge), VFC, FC au repos, respiration et sommeil vs tes moyennes 30 j, tendances |
| **Effort** | Score 0–21 avec l'effort optimal du jour, FC de la journée, activités, zones de FC, calories, pas, tendances |
| **Commencer l'activité** | Carte, suivi d'itinéraire GPS, BPM en direct, objectif d'effort, effort / calories / distance en direct |
| **Activités** | Plus de 150 sports (raquette, collectifs, combat, nautiques, hiver, fitness…), recherche, récents, détection automatique, FC par zones et parcours |
| **Santé** | Moniteur de santé : FC au repos, VFC, respiration, SpO₂ (estimation), température cutanée vs ta norme |
| **Communauté** | Série, résumé de la semaine, records, défis (hors ligne) |
| **Plus** | Profil, bracelet (état, batterie, firmware, synchro, vibration, journal Bluetooth), réglages, données |
| **Coach (W)** | Réponses calculées localement à partir de tes données |

## Comment c'est construit

Woop combine les deux projets demandés :

- **[OpenStrap/edge](https://github.com/OpenStrap/edge)** (et ses bibliothèques `protocol` / `analytics`) :
  la séquence de connexion WHOOP 5.0 qui fonctionne (abonnements 0003 → 0007 → 0005 → 0004, HELLO 0x91
  obligatoire, contrat d'horloge), le décodage des enregistrements v18 (FC, intervalles R-R, mouvement,
  pas, température cutanée, état de sommeil du bracelet), l'acquittement de l'historique (« commit
  avant ACK ») et la méthode d'effort.
- **[ryanbr/noop](https://github.com/ryanbr/noop)** (Swift) : la recette de stadification du sommeil
  (HMM + Viterbi) et le score de récupération (z-scores pondérés, VFC dominante), adaptés ici.

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

- Les mesures sont des **estimations** (méthodes publiées), pas les algorithmes propriétaires de WHOOP :
  les valeurs seront proches mais pas identiques. Woop **n'est pas un dispositif médical**.
- L'oxygène sanguin est une estimation non calibrée issue du bracelet.
- iOS limite l'exécution en arrière-plan : la synchronisation est la plus fiable quand l'app est ouverte.
- Application indépendante, **non affiliée à WHOOP, Inc.** Usage personnel, non commercial.

Licences : voir [LICENSE.md](LICENSE.md).
