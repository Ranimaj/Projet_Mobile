#!/usr/bin/env python3
"""Données de démonstration de la maquette (direction sombre et orange).

Appelé par tool/seed.sh une fois les comptes créés : complète le profil de
Jawher Khalifa, publie annonces, articles, événements, offres et candidatures,
puis ajoute des comptes fictifs (Firestore seulement, sans connexion possible)
pour que l'écran Analytics affiche ~1 248 inscrits sur 30 jours (+12 %),
37 cartes en attente et la répartition 77 / 17 / 6 % par rôle.

Idempotent : identifiants de documents fixes (demo-…), réécrits à chaque
lancement ; les dates sont recalculées par rapport à aujourd'hui.
Bibliothèque standard uniquement.
"""
import json
import os
import random
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

PROJECT = "campusconnect-esprit"
DOCS = f"projects/{PROJECT}/databases/(default)/documents"
FS = f"http://127.0.0.1:8085/v1/{DOCS}"
BUCKET = "campusconnect-esprit.firebasestorage.app"
ST = f"http://127.0.0.1:9199/v0/b/{BUCKET}/o"
# Hôte vu par l'app pour lire les photos : 10.0.2.2 depuis l'émulateur Android,
# localhost pour iOS / web (DEMO_MEDIA_HOST=localhost tool/seed.sh).
MEDIA_HOST = os.environ.get("DEMO_MEDIA_HOST", "10.0.2.2")
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
PHOTOS = os.path.join(ROOT, "assets", "images", "onboarding")

ADMIN = os.environ["ADMIN_UID"]
JAWHER = os.environ["JAWHER_UID"]
RECRUITER = os.environ["RECRUITER_UID"]
STUDENTS = [  # (uid, nom) des comptes étudiants réels créés par seed.sh
    (os.environ["AMEL_UID"], "Amel Ben Salah"),
    (os.environ["SARRA_UID"], "Sarra Trabelsi"),
    (os.environ["YOUSSEF_UID"], "Youssef Gharbi"),
]

NOW = datetime.now(timezone.utc).replace(microsecond=0)
rng = random.Random(2026)


def request(label, url, data=None, method="POST", content_type="application/json"):
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": "Bearer owner", "Content-Type": content_type})
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read() or b"{}")
    except urllib.error.HTTPError as e:
        sys.exit(f"Échec HTTP {e.code} : {label}\n  {e.read()[:300].decode(errors='replace')}")


def value(v):
    """Valeur Python -> valeur REST Firestore."""
    if v is None:
        return {"nullValue": None}
    if isinstance(v, bool):
        return {"booleanValue": v}
    if isinstance(v, int):
        return {"integerValue": str(v)}
    if isinstance(v, float):
        return {"doubleValue": v}
    if isinstance(v, datetime):
        return {"timestampValue": v.strftime("%Y-%m-%dT%H:%M:%SZ")}
    if isinstance(v, (list, tuple)):
        return {"arrayValue": {"values": [value(x) for x in v]}}
    if isinstance(v, dict):
        return {"mapValue": {"fields": {k: value(x) for k, x in v.items()}}}
    return {"stringValue": str(v)}


def commit(label, docs, merge_fields=False):
    """docs : liste de (chemin, champs). Écrit par lots de 500 (limite REST).
    merge_fields : ne réécrit que les champs fournis (updateMask)."""
    for i in range(0, len(docs), 500):
        writes = []
        for path, fields in docs[i:i + 500]:
            w = {"update": {"name": f"{DOCS}/{path}",
                            "fields": {k: value(v) for k, v in fields.items()}}}
            if merge_fields:
                w["updateMask"] = {"fieldPaths": list(fields)}
            writes.append(w)
        request(f"{label} ({i + len(writes)}/{len(docs)})",
                f"{FS}:commit", json.dumps({"writes": writes}).encode())


def upload(name):
    """Dépose une photo du dossier onboarding sous articles/demo/ (lecture
    publique dans storage.rules) et renvoie l'URL que l'app chargera."""
    path = f"articles/demo/{name}"
    with open(os.path.join(PHOTOS, name), "rb") as f:
        request(f"photo {path}", f"{ST}?uploadType=media&name={urllib.parse.quote(path, safe='')}",
                f.read(), content_type="image/jpeg")
    return (f"http://{MEDIA_HOST}:9199/v0/b/{BUCKET}/o/"
            f"{urllib.parse.quote(path, safe='')}?alt=media")


def upload_card(uid):
    """Photo de carte factice, pour que « Voir la carte » l'affiche."""
    path = f"student_cards/{uid}/seed.jpg"
    with open(os.path.join(ROOT, "assets", "images", "cover_campus.jpg"), "rb") as f:
        request(f"photo {path}", f"{ST}?uploadType=media&name={urllib.parse.quote(path, safe='')}",
                f.read(), content_type="image/jpeg")


def ago(days=0, hours=0):
    return NOW - timedelta(days=days, hours=hours)


def ahead(days, hour=9):
    d = NOW + timedelta(days=days)
    return d.replace(hour=hour, minute=0, second=0)


# --- Photos ----------------------------------------------------------------
photo = {n: upload(f"esprit_{n}.jpg") for n in ("team", "lab", "whiteboard", "laptops", "campus")}

# --- Profil de Jawher (écran Profil de la maquette) --------------------------
commit("profil de Jawher", [(f"users/{JAWHER}", {
    "major": "Génie Informatique",
    "year": "4SIM2",
    "createdAt": datetime(2024, 9, 16, 8, tzinfo=timezone.utc),
    "skills": ["Flutter", "Firebase", "Dart", "UI/UX", "Git"],
    "isVerifiedStudent": True,
    "studentCard": {
        "status": "verified",
        "imagePath": f"student_cards/{JAWHER}/seed.jpg",
        "submittedAt": datetime(2026, 10, 9, 10, tzinfo=timezone.utc),
        "reviewedBy": ADMIN,
        "reviewedAt": datetime(2026, 10, 12, 14, tzinfo=timezone.utc),
    },
})], merge_fields=True)

# --- Événements (« À la une » : Hackathon ESPRIT 2026) -------------------------
hackathon = datetime(2026, 11, 8, 9, tzinfo=timezone.utc)
if hackathon <= NOW:  # relancé après la date : samedi suivant
    hackathon = ahead(7 + (5 - NOW.weekday()) % 7)
attendees = [u for u, _ in STUDENTS]
events = [
    ("hackathon", "Hackathon ESPRIT 2026", "Associatif", hackathon, "Bloc E, amphi 3", photo["team"],
     "24 heures pour prototyper une app utile au campus, en équipes de 4. "
     "Mentors, repas et prix pour les trois meilleurs projets.", 86),
    ("foot", "Tournoi de foot inter-classes", "Sport", hackathon + timedelta(days=6), "Terrain ESPRIT Ghazela",
     None, "Phase de poules le matin, finales l'après-midi. Inscription par équipe de 7.", 54),
    ("jobfair", "ESPRIT Job Fair", "Job Fair", hackathon + timedelta(days=11), "Hall du Bloc A",
     photo["campus"], "Plus de 40 entreprises recrutent stagiaires et jeunes diplômés. "
     "Apporte ton CV imprimé.", 212),
    ("ia", "Conférence : IA générative en entreprise", "Conférence", hackathon + timedelta(days=18),
     "Bloc E, amphi 1", photo["whiteboard"], "Retours d'expérience d'ingénieurs ESPRIT alumni.", 97),
    ("culture", "Soirée culturelle des clubs", "Culture", hackathon + timedelta(days=27), "Auditorium",
     None, "Musique, théâtre et stands des clubs étudiants.", 140),
]
commit("événements", [(f"events/demo-{key}", {
    "organizerId": ADMIN, "organizerName": "Club Info ESPRIT" if key == "hackathon" else "Vie étudiante",
    "title": title, "description": desc, "category": cat, "startDate": start,
    "location": place, "latitude": 36.8992, "longitude": 10.1897,
    "registeredUserIds": attendees + [f"demo-user-{n:04d}" for n in range(1, count)],
    "posterUrl": poster,
}) for key, title, cat, start, place, poster, desc, count in events])

# --- Annonces : 2 officielles épinglées + 12 de Jawher -----------------------
annonces = [
    ("officielle-examens", ADMIN, "Administration ESPRIT", "Calendrier des examens du semestre 1",
     "Le calendrier est en ligne. Les examens commencent le 5 janvier ; "
     "vérifiez votre salle sur l'espace étudiant.", "Officielle", True, True, 1),
    ("officielle-cartes", ADMIN, "Administration ESPRIT", "Vérification des cartes étudiantes",
     "Déposez une photo de votre carte depuis votre profil pour obtenir le badge « Étudiant vérifié ».",
     "Officielle", True, False, 3),
]
jawher_posts = [
    ("Perdu & Trouvé", "Clé USB noire trouvée en salle E204", "Gravée « RS ». Je la dépose à l'accueil du Bloc E."),
    ("Générale", "Groupe de révision Flutter", "On se retrouve chaque mardi 17 h en salle E101. Tous niveaux."),
    ("Générale", "Covoiturage Ariana → Ghazela", "Départ 7 h 30 du lundi au jeudi, 2 places libres."),
    ("Perdu & Trouvé", "Carte étudiante perdue", "Au nom de Mehdi B., probablement près de la cafétéria."),
    ("Générale", "Atelier Git pour les 3A", "Initiation aux branches et pull requests, jeudi 14 h."),
    ("Générale", "Recherche binôme PFE mobile", "Projet Flutter + Firebase, sujet déjà validé."),
    ("Perdu & Trouvé", "Écouteurs blancs trouvés", "Oubliés à la bibliothèque, table 12."),
    ("Générale", "Tournoi e-sport du club Info", "Inscriptions ouvertes jusqu'à vendredi."),
    ("Générale", "Partage de notes Réseaux", "Mes notes de cours de 4SIM2 sont dispo, demande en message."),
    ("Perdu & Trouvé", "Parapluie bleu trouvé", "Laissé dans l'amphi 3 après le cours de 10 h."),
    ("Générale", "Club photo : sortie à Sidi Bou Saïd", "Samedi matin, rendez-vous devant le Bloc A."),
    ("Générale", "Bénévoles pour le Hackathon", "Le club Info cherche 10 bénévoles pour l'accueil."),
]
for i, (cat, title, body) in enumerate(jawher_posts):
    annonces.append((f"jawher-{i + 1:02d}", JAWHER, "Jawher Khalifa", title, body, cat, False, False, 2 + i * 3))
commit("annonces", [(f"annonces/demo-{key}", {
    "authorId": author, "authorName": name, "title": title, "content": body, "category": cat,
    "isPinned": pinned, "isUrgent": urgent, "createdAt": ago(days),
    "commentCount": rng.randint(0, 14), "targetMajors": [],
}) for key, author, name, title, body, cat, pinned, urgent, days in annonces])

# --- Vente & Don : 5 articles de Jawher + articles des autres ----------------
articles = [
    ("jawher-thinkpad", JAWHER, "Jawher Khalifa", "Laptop Lenovo ThinkPad T480", 950.0, "Électronique",
     [photo["laptops"]], "i5, 16 Go RAM, SSD 512 Go. Batterie récente, chargeur inclus.", "available"),
    ("jawher-casio", JAWHER, "Jawher Khalifa", "Calculatrice Casio fx-991ES", 45.0, "Électronique",
     [], "Parfait état, idéale pour les examens.", "available"),
    ("jawher-cleancode", JAWHER, "Jawher Khalifa", "Livre « Clean Code »", 35.0, "Livres",
     [], "Édition anglaise, quelques annotations au crayon.", "reserved"),
    ("jawher-ecran", JAWHER, "Jawher Khalifa", "Écran Dell 24 pouces", 280.0, "Électronique",
     [photo["lab"]], "Full HD, câble HDMI fourni.", "available"),
    ("jawher-algo", JAWHER, "Jawher Khalifa", "Cours d'algorithmique (don)", None, "Dons",
     [], "Polycopiés de 1re année, à récupérer au Bloc E.", "available"),
    ("bouilloire", STUDENTS[0][0], STUDENTS[0][1], "Bouilloire et deux mugs", None, "Dons",
     [], "Je déménage, à donner cette semaine.", "available"),
    ("chaise", STUDENTS[1][0], STUDENTS[1][1], "Chaise de bureau ergonomique", 120.0, "Mobilier",
     [], "Réglable en hauteur, très bon état.", "available"),
    ("sweat", STUDENTS[2][0], STUDENTS[2][1], "Sweat ESPRIT taille M", 25.0, "Vêtements",
     [], "Porté deux fois.", "available"),
    ("arduino", STUDENTS[2][0], STUDENTS[2][1], "Kit Arduino Uno complet", 70.0, "Électronique",
     [photo["whiteboard"]], "Capteurs, breadboard et câbles inclus.", "available"),
    ("java", STUDENTS[0][0], STUDENTS[0][1], "Livre « Java, la synthèse »", None, "Dons",
     [], "À donner à un étudiant de 2A.", "available"),
]
commit("articles", [(f"articles/demo-{key}", {
    "ownerId": owner, "ownerName": name, "title": title, "description": desc, "price": price,
    "category": cat, "imageUrls": images, "status": status, "latitude": 36.8992,
    "longitude": 10.1897, "createdAt": ago(i * 2 + 1), "viewCount": rng.randint(8, 160),
    "favoritedBy": [JAWHER] if owner != JAWHER and i % 2 else [],
}) for i, (key, owner, name, title, price, cat, images, desc, status) in enumerate(articles)])

# --- Stage & Emploi : offres + 3 candidatures de Jawher -----------------------
offers = [
    ("vermeg-pfe", RECRUITER, "Vermeg", "Stage PFE : application mobile Flutter", "stage", "Tunis, Lac 2",
     ["Flutter", "Firebase", "Dart"], 4),
    ("vermeg-ete", RECRUITER, "Vermeg", "Stage d'été : back-office Firebase", "stage", "Tunis, Lac 2",
     ["Firebase", "Node.js"], 9),
    ("talan-mobile", RECRUITER, "Talan Tunisie", "Développeur mobile junior", "emploi", "Tunis, Centre Urbain Nord",
     ["Flutter", "Git", "REST"], 6),
    ("instadeep-ia", RECRUITER, "InstaDeep", "Stage PFE : IA et vision par ordinateur", "stage", "Tunis",
     ["Python", "PyTorch"], 12),
    ("sofrecom-uiux", RECRUITER, "Sofrecom", "Stage UI/UX design mobile", "stage", "Tunis, Lac 1",
     ["UI/UX", "Figma"], 2),
    ("proxym-fullstack", RECRUITER, "Proxym Group", "Ingénieur full-stack", "emploi", "Sousse",
     ["Angular", "Spring Boot", "Git"], 15),
]
commit("offres", [(f"job_offers/demo-{key}", {
    "recruiterId": rec, "companyName": company, "title": title,
    "description": f"{company} recherche un profil motivé pour rejoindre son équipe produit.",
    "type": kind, "location": place, "requiredSkills": skills,
    "postedAt": ago(days), "deadline": ahead(30 + days),
}) for key, rec, company, title, kind, place, skills, days in offers])
applied = [("vermeg-pfe", "seen", 3), ("talan-mobile", "sent", 1), ("sofrecom-uiux", "accepted", 8)]
by_key = {o[0]: o for o in offers}
commit("candidatures", [(f"applications/demo-jawher-{key}", {
    "jobOfferId": f"demo-{key}", "jobTitle": by_key[key][3], "companyName": by_key[key][2],
    "candidateId": JAWHER, "cvUrl": None,
    "coverLetter": "Étudiant en 4SIM2, je développe en Flutter et Firebase depuis deux ans.",
    "status": status, "appliedAt": ago(days),
}) for key, status, days in applied])

# --- Comptes fictifs pour l'écran Analytics ------------------------------------
# 30 derniers jours : 1 248 inscrits au total avec les 5 comptes du jour créés
# par seed.sh (Jawher date de 2024), courbe croissante et pic au jour 22.
# 30 jours précédents : 1 114, soit +12 %.
FIRST = ["Aymen", "Mariem", "Skander", "Nour", "Rania", "Mohamed", "Yasmine", "Firas", "Ines", "Oussama",
         "Eya", "Hamza", "Sirine", "Wassim", "Chaima", "Khalil", "Malek", "Asma", "Bilel", "Rim",
         "Ahmed", "Salma", "Anis", "Hiba", "Ghassen", "Emna", "Mehdi", "Fatma", "Seif", "Amira"]
LAST = ["Ben Ali", "Trabelsi", "Jebali", "Mansouri", "Hammami", "Bouazizi", "Gharbi", "Chaabane",
        "Karray", "Dridi", "Ayari", "Sassi", "Mejri", "Baccouche", "Ferchichi", "Zouari", "Khemiri",
        "Jlassi", "Ouertani", "Rekik"]
MAJORS = ["Génie Informatique", "Génie Civil", "Génie Électromécanique", "Génie Télécom", "Business"]
COMPANIES = ["vermeg.tn", "talan.tn", "sofrecom.tn", "instadeep.com", "proxym.tn", "telnet.tn"]


def curve(total, days, rising):
    weights = [(1 + i / days * rising) * rng.uniform(0.85, 1.15) for i in range(days)]
    if rising:
        weights[21] *= 1.9  # le « +84 » de la maquette
    s = sum(weights)
    counts = [int(w / s * total) for w in weights]
    for i in range(total - sum(counts)):
        counts[-1 - i % days] += 1
    return counts


dates = []
for offset, total, rising in ((0, 1243, 1.4), (30, 1114, 0.6)):
    for i, n in enumerate(curve(total, 30, rising)):
        day = NOW - timedelta(days=offset + 29 - i)
        dates += [day.replace(hour=rng.randint(7, 22), minute=rng.randint(0, 59), second=0)
                  for _ in range(n)]
dates.sort()

# Rôles sur l'ensemble des comptes (6 réels inclus) : 77 / 17 / 6 %.
total = len(dates) + 6
roles = (["admin"] * (round(total * 0.06) - 1) + ["recruiter"] * (round(total * 0.17) - 1))
roles += ["student"] * (len(dates) - len(roles))
rng.shuffle(roles)
students = [i for i, r in enumerate(roles) if r == "student"]
pending = set(rng.sample(students, 34))  # + Amel, Sarra, Youssef = 37
verified = set(rng.sample([i for i in students if i not in pending], len(students) // 2))
rejected = set(rng.sample([i for i in students if i not in pending | verified], 40))

docs = []
for i, (created, role) in enumerate(zip(dates, roles)):
    uid = f"demo-user-{i + 1:04d}"
    first, last = rng.choice(FIRST), rng.choice(LAST)
    domain = rng.choice(COMPANIES) if role == "recruiter" else "esprit.tn"
    card = {"status": "none"}
    if i in pending or i in verified or i in rejected:
        card = {"status": "pending" if i in pending else "verified" if i in verified else "rejected",
                "imagePath": f"student_cards/{uid}/seed.jpg", "submittedAt": created + timedelta(hours=2)}
        if i not in pending:
            card |= {"reviewedBy": ADMIN, "reviewedAt": created + timedelta(days=1)}
        if i in rejected:
            card["rejectReason"] = "Photo floue, carte illisible."
    docs.append((f"users/{uid}", {
        "fullName": f"{first} {last}",
        "email": f"{first}.{last.replace(' ', '')}{i + 1}@{domain}".lower(),
        "role": role, "major": rng.choice(MAJORS) if role == "student" else None,
        "year": rng.choice(["1ère année", "2ème année", "3ème année", "4ème année", "5ème année"])
        if role == "student" else None,
        "isVerifiedStudent": i in verified, "isPhoneVerified": False,
        "ratingAverage": 0, "ratingCount": 0, "skills": [], "campus": "ESPRIT Ghazela",
        "disabled": False, "createdAt": created, "studentCard": card,
    }))
commit("comptes fictifs", docs)
for i in pending:
    upload_card(f"demo-user-{i + 1:04d}")

print(f"Données de démo : {len(events)} événements, {len(annonces)} annonces, {len(articles)} articles, "
      f"{len(offers)} offres, {len(applied)} candidatures, {len(docs)} comptes fictifs "
      f"(photos servies par {MEDIA_HOST}).")
