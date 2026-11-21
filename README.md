# WeerWi

**WeerWi** – Application mobile bilingue (français / anglais) de suivi lunaire et météo pour l'Afrique de l'Ouest.

## Fonctionnalités
- Calcul des phases lunaires et visibilité du croissant (via Skyfield & Astral).
- Intégration de l'API gratuite **Open‑Meteo** pour la couverture nuageuse.
- Géolocalisation GPS du dispositif.
- Mode spécial Ramadan avec estimation du premier jour.
- Authentification Firebase (email / Google).
- Export PDF du rapport mensuel (à implémenter).

## Architecture
```
WeerWi/
├─ app/                # FastAPI service
│   ├─ Dockerfile
│   ├─ main.py
│   └─ requirements.txt
├─ docker-compose.yml  # API, PostgreSQL + PostGIS, Redis
├─ flutter/            # Flutter mobile app
│   ├─ lib/main.dart
│   └─ pubspec.yaml
└─ README.md
```

## Prérequis
- Docker + Docker‑Compose (déjà installé sur votre machine).
- Flutter SDK (≥3.0.0 <4.0.0) pour le développement mobile.
- Un compte Firebase (configurer les clés dans `flutter/` – voir le README Firebase).

## Démarrage rapide
```bash
# 1️⃣ Cloner le dépôt (déjà fait) et se placer dans le répertoire
cd weerwi

# 2️⃣ Lancer les services backend
docker compose up -d   # démarre api, db et redis

# 3️⃣ Vérifier l'API
curl http://localhost:8000/   # doit renvoyer {"message":"WeerWi API is up"}

# 4️⃣ Lancer l'application Flutter (sur un appareil ou simulateur)
cd flutter
flutter pub get
flutter run   # sélectionnez Android / iOS / web
```

## Configuration Firebase (Android / iOS)
1. Créez un projet dans la console Firebase.
2. Ajoutez les plateformes Android & iOS.
3. Téléchargez les fichiers `google-services.json` (Android) et `GoogleService-Info.plist` (iOS).
4. Placez‑les respectivement dans `android/app/` et `ios/Runner/`.
5. Dans `pubspec.yaml` les dépendances `firebase_core` et `firebase_auth` sont déjà listées.

## Déploiement
- Le backend est containerisé ; vous pouvez le pousser sur votre serveur dédié avec `docker compose pull && docker compose up -d`.
- L'application Flutter peut être compilée en APK/AAB ou en IPA pour la publier sur les stores.

---
*Ce README a été généré automatiquement. N’hésitez pas à le compléter selon vos besoins.*
