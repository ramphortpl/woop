# Woop — ton WHOOP 5.0, sans abonnement

Application iOS (en français) qui se connecte **directement en Bluetooth** à un bracelet
**WHOOP 5.0 / MG** (et 4.0), récupère son historique et calcule **sur l'iPhone** le sommeil,
la récupération et l'effort, avec une interface calquée sur l'app WHOOP.

Aucun compte, aucun cloud : tout reste sur ton téléphone.

## Télécharger l'IPA

Chaque modification du code reconstruit automatiquement l'application (GitHub Actions, macOS) :

**➜ https://github.com/ramphortpl/woop/releases/download/ipa-latest/Woop.ipa**

L'IPA n'est pas signée : ouvre ce lien depuis ton iPhone ou colle-le dans ton signer
(ESign, Feather, Scarlet, Sideloadly, AltStore…), signe-la puis installe-la.

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

Pas encore de bracelet sous la main ? *Plus › Mode démo* affiche l'interface avec des données simulées
(jamais mélangées à tes vraies données).

## Ce que fait l'app

| Écran | Contenu |
|---|---|
| **Accueil** | Anneaux Sommeil / Récupération / Effort, sélecteur de jour, série 🔥, batterie du bracelet, *Perspectives quotidiennes*, *Activités du jour* (sommeil, siestes, entraînements), *Sommeil de ce soir* (heure de coucher recommandée, alarme), *Mon tableau de bord* |
| **Personnaliser le tableau de bord** | Les 25 indicateurs de WHOOP (VFC, FC au repos, pas, zones de FC hebdo, VO₂ max, calories, effort et récupération, poids, temps de musculation, dette/efficacité/régularité du sommeil, fréquence respiratoire, sommeil réparateur…), réorganisables |
| **Sommeil** | Performance, besoin, hypnogramme (éveil / léger / profond / paradoxal), efficacité, régularité, latence, perturbations, cycles, dette |
| **Récupération** | Score 0–100 % (vert / jaune / rouge) et ses facteurs vs tes moyennes 30 j |
| **Effort** | Score 0–21, courbe de la journée, zones de FC, calories, pas, activités |
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
