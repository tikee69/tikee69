# 🌸 Pétale

**Pétale** est une app iPhone personnelle pour faire le tri dans vos photos. Elle repère les doublons, les photos ratées, les captures d'écran… et **apprend de vos choix** pour vous suggérer quoi supprimer.

Tout fonctionne **sur l'iPhone**, sans internet. Rien n'est supprimé sans votre accord, et les photos supprimées restent 30 jours dans « Supprimés récemment ».

## Ce que fait l'app

| Onglet | Rôle |
|---|---|
| **Accueil** | Espace récupérable, avancement de l'analyse, progression de l'apprentissage |
| **Trier** | Une photo à la fois : ⬅️ supprimer, ➡️ garder, ⬆️ favori. Les photos à supprimer vont dans une corbeille à vider quand vous voulez |
| **Séries** | Photos presque identiques prises au même moment. L'app garde la ou les 2 plus belles (⭐) : plus nettes, mieux exposées, visages réussis |
| **Nettoyer** | Captures d'écran, photos floues, rafales, documents et tickets, grosses vidéos |
| **Pour vous** | **Suggestions** : photos qui ressemblent à celles que vous supprimez (confiance ≥ 80 %). **Albums** : regroupements par thème (plage, chiens, repas…) à valider |

---

## 📲 Installer l'app sur votre iPhone (gratuit)

### Ce qu'il faut
- Votre **MacBook Pro**, avec environ **40 Go libres**
- Votre **iPhone** et son **câble**
- Votre **identifiant Apple** (celui de l'iPhone convient très bien)

### Étape 1 : installer Xcode (une seule fois)
1. Sur le Mac, ouvrez l'**App Store** et cherchez **Xcode**. Installez-le (gratuit, c'est long : ~30 min à 1 h).
2. Ouvrez Xcode une première fois. S'il propose d'installer des composants, cochez **iOS** et acceptez.

### Étape 2 : ajouter votre identifiant Apple dans Xcode (une seule fois)
1. Dans la barre de menu en haut : **Xcode → Réglages… (Settings)** → onglet **Comptes (Accounts)**.
2. Cliquez sur **+** en bas à gauche → **Apple ID** → connectez-vous.

### Étape 3 : télécharger le projet
1. Sur le Mac, allez sur la page GitHub du projet.
2. Choisissez la branche `claude/iphone-photo-management-app-5tvuxv` (menu déroulant en haut à gauche de la liste des fichiers).
3. Bouton vert **Code** → **Download ZIP**.
4. Double-cliquez sur le ZIP téléchargé pour le décompresser.
5. Ouvrez le dossier et double-cliquez sur **`Petale.xcodeproj`** : Xcode s'ouvre.

### Étape 4 : signer l'app avec votre compte
1. Dans la colonne de gauche d'Xcode, cliquez sur **Petale** (l'icône bleue tout en haut).
2. Au centre, sous **TARGETS**, cliquez sur **Petale**, puis sur l'onglet **Signing & Capabilities**.
3. Dans **Team**, choisissez **votre nom (Personal Team)**.
4. Si un message d'erreur rouge parle du « Bundle Identifier », remplacez `com.tikee69.petale` par quelque chose d'unique, par exemple `com.votreprenom.petale`.

### Étape 5 : préparer l'iPhone (une seule fois)
1. Branchez l'iPhone au Mac avec le câble. Sur l'iPhone, touchez **Se fier à cet ordinateur** et entrez votre code.
2. Sur l'iPhone : **Réglages → Confidentialité et sécurité → Mode développeur** → activez-le. L'iPhone redémarre, puis confirmez **Activer**.
   *(Si l'option n'apparaît pas encore, faites l'étape 6 une fois. Elle apparaîtra ensuite.)*

### Étape 6 : lancer l'app 🚀
1. En haut d'Xcode, au centre, cliquez sur le nom de l'appareil et choisissez **votre iPhone**.
2. Cliquez sur le bouton **▶︎** (lecture) en haut à gauche. La première fois, ça prend quelques minutes.
3. Si l'iPhone affiche « Développeur non approuvé » : **Réglages → Général → VPN et gestion de l'appareil** → touchez votre adresse e-mail → **Approuver**.
4. Relancez avec **▶︎**. L'icône 🌸 Pétale apparaît sur votre écran d'accueil.

### Utilisation au quotidien
- Une fois installée, **l'app fonctionne sans le Mac**, partout. Vous pouvez débrancher le câble.
- ⚠️ **Avec un compte Apple gratuit, l'app doit être réinstallée tous les 7 jours.** Quand elle refuse de s'ouvrir, rebranchez l'iPhone, ouvrez le projet dans Xcode et cliquez sur **▶︎**. **Ce que l'app a appris est conservé.**
- 💡 Astuce sans câble : dans Xcode, menu **Window → Devices and Simulators**, sélectionnez votre iPhone et cochez **Connect via network**. Ensuite, la réinstallation hebdomadaire fonctionne en Wi-Fi (iPhone et Mac sur le même réseau).
- ❗ Ne supprimez pas l'app de l'iPhone : vous perdriez ce qu'elle a appris.

---

## 🧠 Comment fonctionne l'IA

1. **Empreinte** : l'IA d'Apple (Vision) résume chaque photo en une liste de ~700 nombres. Deux photos qui se ressemblent ont des empreintes proches.
2. **Séries** : photos aux empreintes très proches et prises à moins de 15 minutes d'écart. La plus belle est choisie selon le score esthétique d'Apple, la netteté, l'exposition et la qualité des visages.
3. **Apprentissage** : chaque photo gardée ou supprimée (dans Pétale **ou dans l'app Photos**) est mémorisée avec son empreinte. Pour une nouvelle photo, Pétale regarde les 10 photos déjà triées qui lui ressemblent le plus. Si vous les avez presque toutes supprimées, elle vous la suggère.
4. Les premières suggestions arrivent après **30 tris** environ. Tous les seuils se règlent dans ⚙️ Réglages.

## Pour les curieux (technique)
- SwiftUI, iOS 18 minimum, aucune dépendance externe.
- `Petale/Core` : logique pure (séries, beauté, suggestions, nettoyage, albums), testée par `Tests/main.swift`.
- `Petale/Services` : accès à Photos, analyse Vision, sauvegarde.
- `Petale/Store` : état de l'app. `Petale/Views` : écrans.
- Chaque envoi sur GitHub lance automatiquement les tests et une compilation complète sur un Mac (onglet **Actions**).
