"""Entraîne l'assistant de conversation de Vente & Don (CampusConnect).

Le modèle reconnaît l'intention d'un message d'acheteur (disponibilité, prix,
négociation, état, lieu de rencontre, livraison…) en français et en darija
tunisienne écrite en lettres latines. L'app répond ensuite avec les
informations de l'annonce (lib/services/ai/chat_assistant.dart).

  1. Génère questions.csv (phrases d'acheteurs par intention, avec variantes).
  2. Découpe chaque phrase en mots et paires de mots (comme l'app).
  3. Entraîne une régression logistique multiclasse (scikit-learn), l'évalue
     sur 20 % de phrases jamais vues, exporte assets/models/chat_model.json.

Lancer :  python tools/chat_model/train_chat_model.py
"""
import csv
import json
import random
import re
from pathlib import Path

import numpy as np
from sklearn.feature_extraction.text import CountVectorizer
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import accuracy_score, classification_report
from sklearn.model_selection import train_test_split

ROOT = Path(__file__).resolve().parents[2]
DATASET = Path(__file__).with_name('questions.csv')
MODEL = ROOT / 'assets' / 'models' / 'chat_model.json'
EXAMPLES = ROOT / 'test' / 'ai' / 'chat_examples.json'
SEED = 7

ACCENTS = {
    'à': 'a', 'â': 'a', 'ä': 'a', 'á': 'a', 'ã': 'a', 'ç': 'c',
    'é': 'e', 'è': 'e', 'ê': 'e', 'ë': 'e', 'î': 'i', 'ï': 'i', 'í': 'i', 'ì': 'i',
    'ô': 'o', 'ö': 'o', 'ó': 'o', 'ò': 'o', 'õ': 'o', 'ù': 'u', 'û': 'u', 'ü': 'u', 'ú': 'u',
    'ÿ': 'y', 'ñ': 'n', 'œ': 'oe', 'æ': 'ae',
}


def normalize(text: str) -> str:
    lower = ''.join(ACCENTS.get(c, c) for c in text.lower())
    return re.sub(r'\s+', ' ', re.sub(r'[^a-z0-9]+', ' ', lower).strip())


def terms(text: str):
    """Mots et paires de mots voisins — identique à chatTerms() en Dart."""
    words = [w for w in normalize(text).split(' ') if w]
    return sorted(set(words + [f'{a} {b}' for a, b in zip(words, words[1:])]))


# --------------------------------------------------------------- phrases
ITEM = ['', 'le livre', 'la lampe', 'l\'article', 'la calculatrice', 'la veste', 'la chaise', 'ton annonce',
        'le vélo', 'l\'objet', 'le pc', 'ça', 'il', 'elle']
INTENTS = {
    'salutation': [
        'bonjour', 'salut', 'bonsoir', 'coucou', 'hello', 'salam', 'aslema', 'ahla', 'cc', 'slt',
        'bonjour à toi', 'salut ça va', 'salam alikom', 'aslema labes', 'hey', 'bjr', 'salut cv',
        'bonsoir ça va', 'salut toi',
    ],
    'disponible': [
        '{item} est toujours disponible', 'c\'est encore dispo', 'toujours dispo', 'il est encore là',
        '{item} est disponible', 'est ce que c\'est toujours en vente', 'tu l\'as encore', 'vous l\'avez toujours',
        'mazel', 'mazel {item}', 'mazelt 3andek', 'mazel mawjoud', 'c\'est vendu', 'déjà vendu',
        'il est pas encore vendu', 'encore disponible', 'dispo', 'il reste', 'elle est encore dispo',
        'je peux encore l\'avoir', 'l\'annonce est toujours valable', 'toujours d\'actualité',
    ],
    'prix': [
        'c\'est combien', 'combien', 'quel est le prix', 'le prix svp', 'combien tu le vends',
        'combien pour {item}', 'qadeh', '9adech', 'bkadech', 'b9adech', 'chhal', 'prix', 'ça coûte combien',
        'tu le vends à combien', 'c\'est quoi le prix', 'il coûte combien', 'quel prix pour {item}',
        'c\'est gratuit', 'c\'est payant', 'il est gratuit', 'c\'est un don',
    ],
    'negociation': [
        'tu peux baisser', 'dernier prix', 'c\'est négociable', 'prix négociable', 'tu fais un prix',
        'je te propose 20 dt', 'je peux te donner 30', 'tu acceptes 15 dinars', 'une petite réduction',
        'c\'est un peu cher', 'trop cher', 'na9es chwaya', 'tna9es', 'akher soum', 'a5er soum',
        'ok pour 25 dt', 'tu le laisses à 40', 'possible de négocier', 'remise possible', 'baisse un peu',
        'je suis étudiant tu peux faire moins', 'moins cher possible',
    ],
    'etat': [
        'il est en bon état', 'quel est l\'état', 'l\'état de {item}', 'il marche bien', 'il fonctionne',
        'il y a des défauts', 'des rayures', 'il est neuf', 'c\'est neuf ou utilisé', 'il est abîmé',
        'des pages manquantes', 'il a combien de temps', 'utilisé combien de temps', 'yekhdem', 'ye5dem mriguel',
        'fih mochkla', 'jdid', 'il est propre', 'pas de problème avec {item}', 'la batterie tient',
        'il y a une garantie',
    ],
    'details': [
        'plus de détails', 'tu peux me décrire {item}', 'c\'est quelle taille', 'quelle marque', 'quel modèle',
        'quelle édition', 'les dimensions', 'quelle couleur', 'c\'est quel auteur', 'caractéristiques',
        'donne moi plus d\'infos', 'c\'est quoi exactement', 'quelle version', 'taille combien', 'chnoua el marka',
        'kifeh shape', 'il fait quelle taille', 'c\'est pour quel niveau', 'la description stp',
    ],
    'lieu': [
        'on se voit où', 'où est ce qu\'on peut se rencontrer', 'on se retrouve quand', 'tu es où',
        'on peut se voir demain', 'je peux passer le récupérer', 'rendez vous où', 'quand je peux le récupérer',
        'on se voit au campus', 'tu es dispo quand', 'à quelle heure', 'je peux venir ce soir',
        'win nitla9aw', 'win nlawjou', 'waktech nitla9aw', 'waktech', 'win enti', 'on fait l\'échange où',
        'tu es à quel bloc', 'à la bibliothèque ça te va', 'je peux le prendre quand', 'on se voit après les cours',
    ],
    'livraison': [
        'tu livres', 'livraison possible', 'tu peux l\'envoyer', 'tu peux me l\'envoyer par la poste',
        'envoi possible', 'tu fais la livraison', 'tu peux me le ramener', 'livraison à domicile',
        'je suis loin tu peux livrer', 'tbaathou', 'tnajem tab3athou', 'livraison', 'envoi par poste',
        'tu peux l\'expédier', 'possible de l\'envoyer à sfax', 'il y a des frais de livraison',
    ],
    'photo': [
        'tu as d\'autres photos', 'plus de photos', 'envoie une photo', 'tu peux envoyer une photo',
        'une photo de près', 'photo réelle', 'je peux voir une photo', 'abaathli taswira', 'taswira',
        'des photos svp', 'une autre photo', 'photo de l\'arrière', 'montre moi {item}',
    ],
    'reserver': [
        'tu peux me le garder', 'réserve le moi', 'garde le pour moi', 'je le prends', 'je le veux',
        'je suis intéressé', 'je suis intéressée', 'je réserve', 'khalih lia', 'na5ou', 'nheb na5ou',
        'mets le de côté', 'tu me le gardes jusqu\'à demain', 'je confirme je le prends', 'ça m\'intéresse',
        'je le prends ok', 'je veux l\'acheter',
    ],
    'merci': [
        'merci', 'merci beaucoup', 'super merci', 'ok merci', 'parfait merci', 'chokran', 'aychek', 'yaichek',
        'merci bien', 'ok d\'accord', 'ça marche', 'top merci', 'nickel', 'parfait', 'très bien merci',
        'merci à toi', 'bonne journée',
    ],
    'autre': [
        'tu étudies quoi', 'tu es en quelle année', 'tu connais le prof de maths', 'il fait beau aujourd\'hui',
        'tu vas à la soirée', 'quelle heure est il', 'tu as d\'autres articles', 'tu vends autre chose',
        'on peut être amis', 'tu es de quelle ville', 'c\'est quoi ton numéro', 'tu as instagram',
        'je cherche un colocataire', 'tu as des cours de java', 'l\'examen est quand', 'chnoua a5barek',
    ],
}
PREFIX = ['', '', '', 'bonjour ', 'salut ', 'bonsoir ', 'slt ', 'aslema ', 'salam ', 'svp ', 'excuse moi ']
SUFFIX = ['', '', '', ' ?', ' svp', ' stp', ' ??', ' merci', ' s\'il te plaît', ' 3afak', ' !']


def typo(rng, s):
    if len(s) < 6 or rng.random() > 0.2:
        return s
    i = rng.randrange(1, len(s) - 1)
    return s[:i] + s[i + 1:]  # lettre oubliée


def build_dataset(per_intent=160):
    rng = random.Random(SEED)
    rows = []
    for intent, phrases in INTENTS.items():
        for _ in range(per_intent):
            p = rng.choice(phrases).replace('{item}', rng.choice(ITEM)).strip()
            pre = '' if intent in ('salutation', 'merci') else rng.choice(PREFIX)
            s = typo(rng, pre + p + rng.choice(SUFFIX))
            if rng.random() < 0.3:
                s = s.capitalize()
            rows.append((s, intent))
    rows = list(dict.fromkeys(rows))  # sans doublons
    rng.shuffle(rows)
    with DATASET.open('w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh)
        w.writerow(['message', 'intention'])
        w.writerows(rows)
    return rows


def main():
    rows = build_dataset()
    texts = [t for t, _ in rows]
    y = np.array([i for _, i in rows])
    tr, te = train_test_split(np.arange(len(rows)), test_size=0.2, random_state=SEED, stratify=y)
    vec = CountVectorizer(analyzer=terms, binary=True, min_df=2)
    Xtr = vec.fit_transform([texts[i] for i in tr])
    model = LogisticRegression(C=4.0, max_iter=5000)
    model.fit(Xtr, y[tr])
    Xte = vec.transform([texts[i] for i in te])
    pred = model.predict(Xte)
    print(classification_report(y[te], pred, digits=3))

    classes = list(model.classes_)
    vocab = {}
    for term, j in sorted(vec.vocabulary_.items()):
        ws = [round(float(model.coef_[k][j]), 3) for k in range(len(classes))]
        if any(abs(w) >= 0.02 for w in ws):
            vocab[term] = ws
    out = {
        'name': 'campusconnect-chat',
        'version': 1,
        'type': 'logistic_regression_multiclass',
        'classes': classes,
        'bias': [round(float(b), 4) for b in model.intercept_],
        'terms': vocab,
        'minConfidence': 0.45,
        'metrics': {
            'phrases': len(rows),
            'test': int(len(te)),
            'accuracy': round(accuracy_score(y[te], pred), 3),
        },
    }
    MODEL.write_text(json.dumps(out, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')

    proba = model.predict_proba(Xte[:40])
    EXAMPLES.write_text(json.dumps([
        {'message': texts[i], 'intent': classes[int(np.argmax(p))], 'confidence': round(float(max(p)), 6)}
        for i, p in zip(te[:40], proba)
    ], ensure_ascii=False, indent=1), encoding='utf-8')
    print(out['metrics'], 'termes :', len(vocab))


if __name__ == '__main__':
    main()
