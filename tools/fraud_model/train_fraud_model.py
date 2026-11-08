"""Entraîne le modèle anti-arnaque de Vente & Don (CampusConnect).

Étapes :
  1. Génère un jeu de données d'annonces étudiantes (annonces.csv) :
     annonces normales et annonces d'arnaque, avec du « bruit » réaliste
     (vraies annonces urgentes, arnaques discrètes…).
  2. Calcule les caractéristiques (les mêmes que dans l'app, fichier
     lib/services/ai/fraud_detector.dart).
  3. Entraîne une régression logistique (scikit-learn), l'évalue sur 20 %
     d'annonces jamais vues et exporte les poids dans
     assets/models/fraud_model.json, lu par l'app sans internet.

Lancer :  python tools/fraud_model/train_fraud_model.py
"""
import csv
import json
import random
import re
from pathlib import Path

import numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, confusion_matrix, f1_score, precision_score, recall_score
from sklearn.model_selection import train_test_split

ROOT = Path(__file__).resolve().parents[2]
DATASET = Path(__file__).with_name('annonces.csv')
MODEL = ROOT / 'assets' / 'models' / 'fraud_model.json'
# Exemples recalculés par le test Dart : garantit que l'app calcule
# exactement comme ici (test/ai/fraud_detector_test.dart).
EXAMPLES = ROOT / 'test' / 'ai' / 'fraud_examples.json'
SEED = 42

# ---------------------------------------------------------------- features
# Doit rester identique à fraud_detector.dart.
ACCENTS = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'ç': 'c',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i',
    'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
    'ÿ': 'y', 'ñ': 'n', 'œ': 'oe', 'æ': 'ae',
}


def normalize(text: str) -> str:
    lower = ''.join(ACCENTS.get(c, c) for c in text.lower())
    return re.sub(r'\s+', ' ', re.sub(r'[^a-z0-9]+', ' ', lower).strip())


GROUPS = {
    'payment': ['avance', 'acompte', 'virement', 'd17', 'flouci', 'mandat', 'western union',
                'paiement avant', 'payer avant', 'payez avant', 'paiement d abord', 'recharge',
                'carte cadeau', 'transfert', 'rib', 'e dinar', 'edinar', 'frais de livraison',
                'frais d envoi'],
    'off_app': ['whatsapp', 'telegram', 'messenger', 'instagram', 'insta', 'snapchat', 'viber'],
    'urgency': ['urgent', 'urgence', 'vite', 'rapidement', 'aujourd hui seulement',
                'premier arrive', 'derniere chance', 'depechez', 'dernier jour', 'offre limitee'],
    'no_meeting': ['livraison seulement', 'uniquement livraison', 'pas de rencontre',
                   'pas de remise en main propre', 'envoi par poste', 'par la poste',
                   'a l etranger', 'hors campus', 'pas sur le campus', 'envoi uniquement'],
    'high_value': ['iphone', 'macbook', 'ipad', 'airpods', 'ps5', 'playstation', 'galaxy',
                   'rolex', 'laptop', 'pc portable', 'ordinateur portable', 'xbox',
                   'nintendo switch', 'apple watch', 'gopro', 'drone'],
    'too_good': ['sous blister', 'jamais utilise', 'jamais servi', '100 neuf', 'original garanti',
                 'prix sacrifie', 'prix casse', 'cadeau'],
}
PHONE = re.compile(r'(\+?216)?[\s.-]?\b[2-9]\d(?:[\s.-]?\d{3}){2}\b')
EMAIL = re.compile(r'[\w.+-]+@[\w-]+\.[\w.]+')
LINK = re.compile(r'(https?://|www\.)\S+', re.IGNORECASE)
REFERENCE_LOW = {'Livres': 10, 'Électronique': 30, 'Vêtements': 10, 'Mobilier': 20, 'Autre': 5}
FEATURES = ['payment', 'off_app', 'urgency', 'no_meeting', 'high_value_cheap',
            'price_far_below', 'too_good', 'free_but_pay', 'short_description', 'no_photo', 'shouting']


def has_any(norm: str, phrases) -> bool:
    padded = f' {norm} '
    return any(f' {p} ' in padded for p in phrases)


def features(title, description, category, price, has_photo):
    norm = normalize(f'{title} {description}')
    raw = f'{title}\n{description}'
    f = {
        'payment': has_any(norm, GROUPS['payment']),
        'off_app': has_any(norm, GROUPS['off_app']) or bool(PHONE.search(raw) or EMAIL.search(raw) or LINK.search(raw)),
        'urgency': has_any(norm, GROUPS['urgency']),
        'no_meeting': has_any(norm, GROUPS['no_meeting']),
        'high_value_cheap': price is not None and price < 150 and has_any(norm, GROUPS['high_value']),
        'price_far_below': 0.0 if price is None else max(0.0, min(1.0, 1 - price / REFERENCE_LOW.get(category, 5))),
        'too_good': has_any(norm, GROUPS['too_good']),
        'free_but_pay': price is None and has_any(norm, GROUPS['payment']),
        'short_description': len(normalize(description).split()) < 8,
        'no_photo': not has_photo,
    }
    letters = re.sub(r'[^A-Za-zÀ-ÿ]', '', title)
    f['shouting'] = raw.count('!') >= 3 or (len(letters) >= 6 and letters == letters.upper())
    return [float(f[name]) for name in FEATURES]


# ----------------------------------------------------------------- dataset
ITEMS = {
    'Livres': [('Livre d\'algorithmique', 8, 30), ('Cours d\'analyse 1ère année', 5, 20),
               ('Roman Le Petit Prince', 5, 15), ('Livre de Java', 10, 35),
               ('Annales de physique', 5, 20), ('Dictionnaire français-anglais', 8, 25)],
    'Électronique': [('Calculatrice scientifique Casio', 25, 60), ('Clavier mécanique', 40, 120),
                     ('Souris sans fil', 15, 40), ('Écouteurs Bluetooth', 25, 80),
                     ('iPhone 11 64 Go', 550, 900), ('PC portable HP i5', 700, 1300),
                     ('Disque dur externe 1 To', 80, 150), ('Samsung Galaxy A52', 400, 650),
                     ('AirPods Pro', 300, 500), ('Manette PS5', 120, 200)],
    'Vêtements': [('Veste d\'hiver', 20, 70), ('Blouse de labo', 10, 25), ('Jean taille 40', 15, 40),
                  ('Baskets taille 42', 30, 90), ('Pull en laine', 15, 35)],
    'Mobilier': [('Lampe de bureau LED', 15, 40), ('Chaise de bureau', 40, 120), ('Petite étagère', 25, 70),
                 ('Table pliante', 30, 80), ('Matelas 1 place', 60, 150)],
    'Autre': [('Vélo de ville', 120, 300), ('Raquette de tennis', 30, 80), ('Bouilloire', 15, 35),
              ('Sac à dos', 15, 50), ('Guitare classique', 80, 200)],
}
STATES = ['Très bon état', 'Bon état', 'Comme neuf', 'Quelques traces d\'usure', 'Utilisé un semestre']
LEGIT_BODY = [
    '{state}, {detail}. Remise en main propre sur le campus, à la cafétéria ou devant la bibliothèque.',
    '{state}. {detail}. On peut se voir au bloc A entre deux cours pour que tu le vérifies.',
    'Je le vends car je n\'en ai plus besoin. {state}, {detail}. Rendez-vous sur le campus.',
    '{state}, {detail}. Tu peux l\'essayer avant de payer, on se retrouve à l\'entrée de l\'école.',
    '{detail}. {state}. Disponible après 16h sur le campus, paiement en espèces à la remise.',
]
DETAILS = ['fonctionne parfaitement', 'aucune pièce manquante', 'propre et bien entretenu',
           'acheté l\'année dernière', 'facture disponible', 'idéal pour les révisions',
           'livré avec son chargeur', 'jamais tombé']
LEGIT_SHORT = ['{state}.', 'À récupérer sur le campus.', '{state}, prix à discuter.']
LEGIT_NOISE = [
    'Je déménage, c\'est urgent, merci de me contacter rapidement via la messagerie.',
    'Je pars en stage, je dois vendre vite. Rendez-vous sur le campus.',
    'Écris-moi aussi sur WhatsApp si tu préfères, on se voit au campus.',
    'Jamais utilisé, reçu en cadeau. On se voit au campus.',
    'Si tu habites loin je peux l\'envoyer par la poste, sinon on se voit au campus.',
    'Prix sacrifié car je pars à la fin du mois.',
    'TRÈS BON PRIX !!! À voir vite !',
]
SCAM_SIGNALS = {
    'payment': ['Paiement par virement avant l\'envoi.', 'Il faut payer une avance de {adv} DT par D17 pour réserver.',
                'Envoyez un acompte par Flouci et je vous l\'envoie.', 'Paiement d\'abord, recharge téléphonique acceptée.',
                'Seulement des frais de livraison à payer avant par mandat.'],
    'off_app': ['Contactez-moi sur WhatsApp au 2{n1} {n2} {n3}.', 'Écrivez sur Telegram, je ne réponds pas ici.',
                'Plus de photos sur instagram, envoyez-moi un message là-bas.', 'Mon mail : vente{n1}@gmail.com',
                'Voir www.bonplan-{n1}.com pour commander.'],
    'urgency': ['URGENT !!! Premier arrivé premier servi.', 'Offre limitée, aujourd\'hui seulement !',
                'Dépêchez-vous, dernière chance !!', 'Il faut faire vite, beaucoup de demandes.'],
    'no_meeting': ['Livraison seulement, pas de rencontre.', 'Je suis à l\'étranger, envoi par la poste.',
                   'Pas de remise en main propre, envoi uniquement.', 'Je ne suis pas sur le campus, livraison seulement.'],
}
SCAM_ITEMS = [('iPhone 14 Pro neuf', 'Électronique'), ('MacBook Air M2', 'Électronique'), ('PS5 avec 2 manettes', 'Électronique'),
              ('AirPods Pro 2', 'Électronique'), ('iPad Air', 'Électronique'), ('Samsung Galaxy S23', 'Électronique'),
              ('Apple Watch', 'Électronique'), ('PC portable gamer', 'Électronique'), ('Rolex originale', 'Autre'),
              ('Veste de marque', 'Vêtements'), ('Canapé cuir', 'Mobilier'), ('Livres de médecine (lot)', 'Livres'),
              ('Nintendo Switch', 'Électronique'), ('Drone 4K', 'Autre')]


def legit(rng):
    category = rng.choice(list(ITEMS))
    title, lo, hi = rng.choice(ITEMS[category])
    price = None if rng.random() < 0.12 else float(round(rng.uniform(lo, hi)))
    if rng.random() < 0.15:
        body = rng.choice(LEGIT_SHORT).format(state=rng.choice(STATES))
    else:
        body = rng.choice(LEGIT_BODY).format(state=rng.choice(STATES), detail=rng.choice(DETAILS))
    if rng.random() < 0.25:
        body += ' ' + rng.choice(LEGIT_NOISE)
    if rng.random() < 0.05 and price is not None:
        price = float(round(price * rng.uniform(0.3, 0.6)))  # vraie bonne affaire
    has_photo = rng.random() > 0.12
    return title, body, category, price, has_photo, 0


def scam(rng):
    title, category = rng.choice(SCAM_ITEMS)
    k = 1 if rng.random() < 0.35 else rng.randint(2, 4)  # 35 % d'arnaques discrètes
    signals = rng.sample(list(SCAM_SIGNALS), k)
    parts = [rng.choice(['Comme neuf.', 'Neuf sous blister, jamais utilisé.', 'Très bon état.', ''])]
    parts = [p for p in parts if p]
    for s in signals:
        parts.append(rng.choice(SCAM_SIGNALS[s]).format(adv=rng.randint(20, 100), n1=rng.randint(10, 99),
                                                      n2=rng.randint(100, 999), n3=rng.randint(100, 999)))
    rng.shuffle(parts)
    r = rng.random()
    price = float(rng.randint(20, 140)) if r < 0.6 else (None if r < 0.7 else float(rng.randint(150, 600)))
    if rng.random() < 0.25:
        title = title.upper()
    has_photo = rng.random() > 0.35
    return title, ' '.join(parts), category, price, has_photo, 1


def build_dataset(n_legit=900, n_scam=450):
    rng = random.Random(SEED)
    rows = [legit(rng) for _ in range(n_legit)] + [scam(rng) for _ in range(n_scam)]
    # 3 % d'étiquettes « bruitées » : dans la vraie vie, l'étiquetage n'est jamais parfait.
    rows = [r[:-1] + (1 - r[-1],) if rng.random() < 0.03 else r for r in rows]
    rng.shuffle(rows)
    with DATASET.open('w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh)
        w.writerow(['titre', 'description', 'categorie', 'prix', 'photo', 'arnaque'])
        for t, d, c, p, ph, y in rows:
            w.writerow([t, d, c, '' if p is None else int(p), int(ph), y])
    return rows


# ------------------------------------------------------------------- train
def main():
    rows = build_dataset()
    X_feat = np.array([features(t, d, c, p, ph) for t, d, c, p, ph, _ in rows])
    y = np.array([r[-1] for r in rows])

    idx_train, idx_test = train_test_split(np.arange(len(rows)), test_size=0.2, random_state=SEED, stratify=y)

    def matrix(ids):
        return X_feat[ids]

    model = LogisticRegression(C=1.0, max_iter=2000)
    model.fit(matrix(idx_train), y[idx_train])
    pred = model.predict(matrix(idx_test))

    metrics = {
        'annonces': len(rows),
        'test': int(len(idx_test)),
        'accuracy': round(accuracy_score(y[idx_test], pred), 3),
        'precision': round(precision_score(y[idx_test], pred), 3),
        'recall': round(recall_score(y[idx_test], pred), 3),
        'f1': round(f1_score(y[idx_test], pred), 3),
        'confusion': confusion_matrix(y[idx_test], pred).tolist(),
    }
    coef = model.coef_[0]
    out = {
        'name': 'campusconnect-fraud',
        'version': 1,
        'type': 'logistic_regression',
        'bias': round(float(model.intercept_[0]), 4),
        'features': {name: round(float(coef[i]), 4) for i, name in enumerate(FEATURES)},
        'thresholds': {'medium': 0.3, 'high': 0.6},
        'metrics': metrics,
    }
    MODEL.parent.mkdir(parents=True, exist_ok=True)
    MODEL.write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding='utf-8')
    probs = model.predict_proba(X_feat[idx_test[:40]])[:, 1]
    examples = [
        {'title': rows[i][0], 'description': rows[i][1], 'category': rows[i][2], 'price': rows[i][3],
         'hasPhoto': rows[i][4], 'probability': round(float(pr), 6)}
        for i, pr in zip(idx_test[:40], probs)
    ]
    EXAMPLES.write_text(json.dumps(examples, ensure_ascii=False, indent=1), encoding='utf-8')
    print(json.dumps(metrics, indent=1))
    print('poids :', out['features'])


if __name__ == '__main__':
    main()
