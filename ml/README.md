# Classifieur de catégorie d'événement

Petit modèle d'apprentissage automatique qui suggère la catégorie d'un événement
(Conférence, Carrière, Sport, Culture, Vie associative) à partir de son titre et de sa description.
Il tourne **dans le téléphone** (aucune connexion, aucune clé, aucun serveur).

## Méthode
1. **Texte → nombres** : on enlève majuscules et accents, on découpe en mots, on retire les mots vides
   (« le », « de »…), puis on ajoute les paires de mots voisins. Chaque terme reçoit un poids TF-IDF
   (TF sous-linéaire `1 + ln(n)`, IDF lissé, normalisation L2).
2. **Nombres → catégorie** : régression logistique multi-classes (une note par catégorie, puis softmax).
3. **Export** : le vocabulaire, les IDF, les coefficients et les biais sont écrits dans
   `assets/ml/category_model.json` (~39 Ko). L'application recalcule exactement les mêmes étapes en Dart.
4. **Seuil de confiance** : en dessous de 45 %, l'application ne propose rien.

## Données
`ml/dataset.py` : 295 exemples en français (titre + description), environ 60 par catégorie, rédigés à la main.
Aucune donnée personnelle.

## Évaluation (reproductible : `python train.py`)
| Mesure | Résultat |
|---|---|
| Test 80/20 (59 exemples jamais vus à l'entraînement) | 94,9 % |
| Validation croisée 5 plis | 90,2 % (écart-type 2,2 %) |
| 30 titres courts écrits à part | 86,7 % |
| Base de comparaison (toujours la même classe) | 20,3 % |
| Avec seuil 45 % : part des cas où l'on propose / précision | 89 % / 94,8 % |

## Limites (à dire honnêtement)
- Petit jeu de données écrit à la main : les résultats sont **optimistes** par rapport à de vrais textes d'étudiants.
- Un mot inconnu (par exemple « Job fair », en anglais) n'apporte aucune information ; le seuil évite alors de proposer.
- Le modèle ne remplace pas le choix de l'organisateur : c'est une **suggestion**, appliquée seulement s'il la touche.
- Pour l'améliorer : ajouter de vrais événements au jeu de données puis relancer `train.py`.

## Régénérer le modèle
```
pip install scikit-learn numpy
cd ml
python train.py
```
Le script réécrit `assets/ml/category_model.json` et `test/fixtures/category_golden.json`
(exemples de référence pour vérifier que Dart et Python donnent les mêmes probabilités).
