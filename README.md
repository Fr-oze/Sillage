# Sillage

**Les quatre saisons passent par tes fenêtres.**

Sillage est une petite app macOS qui fait tomber des flocons, des pétales, du sable ou des feuilles sur ton bureau. Les particules s’accumulent sur les bords visibles des fenêtres et tombent sur celles du dessous quand tu déplaces ou rétrécis une fenêtre.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-24292f)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-24292f)
![Swift](https://img.shields.io/badge/Swift-SwiftUI%20%2B%20SpriteKit-F05138)

| Saison | Sur le bureau | Pour nettoyer |
| --- | --- | --- |
| ❄️ Hiver | Flocons de neige | Chasse-neige |
| 🌸 Printemps | Pétales de cerisier | Balayeur |
| ☀️ Été | Grains de sable dorés | Ratisseur |
| 🍂 Automne | Feuilles mortes | Souffleur à dos |

## Ouvrir Sillage

**Prérequis** — macOS 14 ou plus récent sur un Mac Apple Silicon.

Si tu as reçu l’archive, décompresse-la et ouvre **Sillage.app**. L’app apparaît dans la barre des menus. Les builds locaux portent une signature ad hoc et macOS peut bloquer l’ouverture d’une copie téléchargée. Ouvre uniquement une copie issue d’une source de confiance.

Dans **Réglages**, laisse la saison sur **Automatique** ou choisis une saison pour l’essayer. Tu peux régler la quantité, la taille, la vitesse et le vent, puis lancer le nettoyage depuis le bouton du bas.

L’effet vise 15 images/s au repos et 30 images/s pendant les déplacements, le redimensionnement et le nettoyage. L’accumulation sur le Dock dépend de la disponibilité de son bord dans macOS.

## Compiler depuis le code source

Avec les outils en ligne de commande Apple installés, lance ces commandes à la racine du dépôt.

```sh
./build.sh
open dist/Sillage.app
```

Le script construit une app arm64 signée localement. Il utilise Swift Package Manager puis, si nécessaire, le compilateur Swift directement. Les effets sont dessinés dans SpriteKit et les réglages utilisent SwiftUI, sans dépendance externe.

## Structure

| Dossier | Contenu |
| --- | --- |
| `Sources/Neige/` | Application, effets et suivi des fenêtres |
| `Resources/` | Métadonnées du bundle macOS |
| `Tests/` | Vérifications de la géométrie, de l’accumulation et du redimensionnement |
