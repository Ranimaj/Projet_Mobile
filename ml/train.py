# -*- coding: utf-8 -*-
import json, re, unicodedata, math, sys, os
from pathlib import Path
from collections import Counter
import numpy as np
from sklearn.feature_extraction.text import TfidfVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.model_selection import train_test_split, StratifiedKFold
from sklearn.metrics import accuracy_score, confusion_matrix, classification_report
from dataset import DATA

ROOT = Path(__file__).resolve().parent.parent
OUT_MODEL = ROOT / "assets" / "ml" / "category_model.json"
OUT_GOLD = ROOT / "test" / "fixtures" / "category_golden.json"
THRESHOLD = 0.45  # en dessous, aucune suggestion
CLASSES = ["Conférence", "Carrière", "Sport", "Culture", "Vie associative"]
STOP = set("le la les un une des de du d l et en au aux a à pour par sur avec dans ce cette ces son sa ses leur leurs qui que quoi ou est sont etre est-ce plus tout tous toute toutes pas ne se si y il elle ils elles on nous vous je tu votre vos notre nos mes ma mon ta ton tes dont apres avant entre sans sous chez vers comme aussi mais donc or ni car".split())

def normalize(s):
    s = unicodedata.normalize("NFD", s.lower())
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    return s

def tokenize(text):
    toks = re.findall(r"[a-z0-9]+", normalize(text))
    toks = [t for t in toks if len(t) >= 2 and t not in STOP]
    feats = list(toks)
    feats += [a + "_" + b for a, b in zip(toks, toks[1:])]
    return feats

texts = [t for t, _ in DATA]
y = np.array([CLASSES.index(c) for _, c in DATA])

def make_vec():
    return TfidfVectorizer(analyzer=tokenize, sublinear_tf=True, norm="l2", min_df=2)

def make_clf():
    return LogisticRegression(C=10.0, max_iter=2000)

# 1) split 80/20 stratifié
Xtr, Xte, ytr, yte = train_test_split(texts, y, test_size=0.2, stratify=y, random_state=42)
vec = make_vec(); A = vec.fit_transform(Xtr); clf = make_clf().fit(A, ytr)
pred = clf.predict(vec.transform(Xte))
acc = accuracy_score(yte, pred)
print(f"[split 80/20] train={len(Xtr)} test={len(Xte)} accuracy={acc:.3f}")
print(classification_report(yte, pred, target_names=CLASSES, digits=3, zero_division=0))
print("confusion (lignes = vrai, colonnes = prédit)\n", confusion_matrix(yte, pred))

# 2) validation croisée 5 plis
accs = []
skf = StratifiedKFold(n_splits=5, shuffle=True, random_state=7)
for tr, te in skf.split(texts, y):
    v = make_vec(); a = v.fit_transform([texts[i] for i in tr]); c = make_clf().fit(a, y[tr])
    accs.append(accuracy_score(y[te], c.predict(v.transform([texts[i] for i in te]))))
print(f"[5-fold CV] accuracies={['%.3f'%a for a in accs]} mean={np.mean(accs):.3f} std={np.std(accs):.3f}")

# 3) base de comparaison : toujours prédire la classe majoritaire
maj = Counter(ytr).most_common(1)[0][0]
print(f"[baseline classe majoritaire] accuracy={np.mean(yte == maj):.3f}  (hasard = {1/len(CLASSES):.3f})")

# 4) jeu « titres courts » réalistes, écrits à part, jamais utilisés pour l'entraînement
SHORT = [
 ("Tournoi de foot", "Sport"), ("Match de basket entre classes", "Sport"), ("Course à pied du campus", "Sport"),
 ("Séance de yoga", "Sport"), ("Compétition de natation", "Sport"), ("Tournoi de volley", "Sport"),
 ("Forum emploi", "Carrière"), ("Atelier CV et lettre de motivation", "Carrière"), ("Rencontre avec des recruteurs", "Carrière"),
 ("Job fair ESPRIT", "Carrière"), ("Offre de stage PFE", "Carrière"), ("Simulation d'entretien", "Carrière"),
 ("Conférence sur l'IA", "Conférence"), ("Séminaire de cybersécurité", "Conférence"), ("Colloque de recherche", "Conférence"),
 ("Conférence climat", "Conférence"), ("Soutenance de thèse", "Conférence"), ("Table ronde sur le numérique", "Conférence"),
 ("Concert de musique", "Culture"), ("Exposition de peinture", "Culture"), ("Soirée cinéma", "Culture"),
 ("Pièce de théâtre", "Culture"), ("Festival de poésie", "Culture"), ("Atelier de calligraphie", "Culture"),
 ("Assemblée générale du club", "Vie associative"), ("Journée d'intégration", "Vie associative"), ("Collecte de dons", "Vie associative"),
 ("Don du sang", "Vie associative"), ("Réunion du bureau des étudiants", "Vie associative"), ("Nettoyage du campus", "Vie associative"),
]
vfull = make_vec(); Afull = vfull.fit_transform(texts); cfull = make_clf().fit(Afull, y)
ps = cfull.predict(vfull.transform([t for t, _ in SHORT]))
ys = np.array([CLASSES.index(c) for _, c in SHORT])
print(f"[titres courts, {len(SHORT)} exemples] accuracy={np.mean(ps == ys):.3f}")
for (t, c), p in zip(SHORT, ps):
    if CLASSES[p] != c:
        print("   erreur :", t, "| vrai =", c, "| prédit =", CLASSES[p])

# 5) export du modèle final (entraîné sur tout le jeu) pour Dart
vocab = vfull.vocabulary_
idf = vfull.idf_
coef = cfull.coef_      # (n_classes, n_features)
inter = cfull.intercept_
model = {
    "version": 1,
    "threshold": THRESHOLD,
    "classes": CLASSES,
    "stopwords": sorted(STOP),
    "intercepts": [round(float(b), 6) for b in inter],
    "terms": {tok: [round(float(idf[i]), 6)] + [round(float(coef[k, i]), 6) for k in range(len(CLASSES))]
              for tok, i in vocab.items()},
}
OUT_MODEL.parent.mkdir(parents=True, exist_ok=True)
json.dump(model, open(OUT_MODEL, "w", encoding="utf-8"), ensure_ascii=False, separators=(",", ":"))

# 6) vecteurs de référence pour tester la parité Dart/Python
def predict_manual(text):
    toks = tokenize(text)
    cnt = Counter(t for t in toks if t in model["terms"])
    x = {t: (1 + math.log(c)) * model["terms"][t][0] for t, c in cnt.items()}
    norm = math.sqrt(sum(v * v for v in x.values()))
    scores = list(model["intercepts"])
    if norm > 0:
        for t, v in x.items():
            for k in range(len(CLASSES)):
                scores[k] += (v / norm) * model["terms"][t][1 + k]
    m = max(scores); e = [math.exp(s - m) for s in scores]; z = sum(e)
    return [v / z for v in e]

gold_texts = [
 "Tournoi de football inter-classes. Équipes de sept joueurs au stade du campus.",
 "Forum de l'emploi. Rencontrez des recruteurs et déposez votre CV.",
 "Conférence sur l'intelligence artificielle et ses applications.",
 "Concert de musique andalouse dans la cour de l'école.",
 "Assemblée générale du club de robotique et élection du bureau.",
 "Zzzz qqqq",
]
gold = []
for t in gold_texts:
    p = predict_manual(t)
    sk = cfull.predict_proba(vfull.transform([t]))[0]
    assert np.allclose(p, sk, atol=1e-4), (t, p, sk)   # parité sklearn / reimplémentation
    gold.append({"text": t, "probs": [round(v, 5) for v in p]})
OUT_GOLD.parent.mkdir(parents=True, exist_ok=True)
json.dump(gold, open(OUT_GOLD, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("modèle:", len(vocab), "termes,", round(os.path.getsize(OUT_MODEL)/1024, 1), "Ko")

# 7) mots les plus influents par classe (unigrammes)
print("\nMots les plus influents par classe :")
inv = {i: t for t, i in vocab.items()}
for k, c in enumerate(CLASSES):
    order = np.argsort(-coef[k])
    top = [inv[i] for i in order if "_" not in inv[i]][:8]
    print(f"  {c}: {', '.join(top)}")
