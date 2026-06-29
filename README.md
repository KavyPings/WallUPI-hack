# Wallupi

**AI-powered fraud detection for UPI payments — Flutter + Flask + Amazon Bedrock**

Wallupi is a mock UPI payment app that intercepts potentially fraudulent transactions in real time using a three-tier AI stack running entirely on-device and in the cloud. Every payment goes through a risk assessment before it is allowed to proceed.

---

## What it does

When you try to send money, Wallupi silently checks:

- Is the recipient new or previously flagged by the community?
- Are you on a phone call with an unknown number right now?
- Did a suspicious SMS arrive recently that mentions this recipient?
- Is the amount unusually large compared to your history?
- Was the payment triggered by a QR code or external link?

Based on those signals it assigns a **risk score (0–100)** and routes you through one of four outcomes:

| Score | Tier | What happens |
|-------|------|-------------|
| 0 – 49 | Safe | Payment goes through immediately |
| 50 – 79 | Soft warning | A review popup with risk factors |
| 80 – 94 | Strong warning | Full warning screen + must tick a checkbox |
| 95 – 100 | Critical | 10-second forced delay + checkbox before proceeding |

---

## Three-tier SMS fraud detection

Every SMS in the inbox is run through three layers in sequence:

### Tier 1 — Rule Engine (on-device, ~1ms)
Heuristic scoring using keyword categories, sender patterns, URL detection, and compound multipliers. Runs with no internet and no ML. Scores above 85% skip Tier 2 entirely (obvious scam). Scores below 15% skip Tier 2 (obvious safe). Everything in between escalates.

### Tier 2 — TinyBERT (on-device TFLite, ~50ms)
A quantized BERT model classifies the SMS into fraud categories: OTP theft, phishing, fake KYC, UPI fraud, social engineering, APK malware, fake banking alert. The model is additive only — a universal rule score floor prevents TinyBERT from reducing a score the rule engine already flagged.

**Cloud escalation triggers** (any one is sufficient):
- TinyBERT confidence below threshold (uncertain about its own output)
- TinyBERT says **safe ≥80%** but rule engine scores **≥45%** — the contradiction is treated as a signal (`modelDisagreesWithRules`)
- TinyBERT model file not available on device

Escalation only fires when combined risk ≥55%.

### Tier 3 — Cloud LLM (gpt-oss-120b on Amazon Bedrock, ~2–5s)
When Tier 2 triggers escalation, a PII-sanitized copy of the SMS is sent to GPT-OSS 120B via the Amazon Bedrock OpenAI-compatible endpoint (`bedrock-mantle`). The model returns a refined risk score, classification, intervention level, plain-English explanation, and key fraud indicators.

The result updates the stored message analysis and is shown in the SMS analysis screen as a "Cloud AI Review" card.

---

## Tech stack

| Layer | Technology |
|-------|-----------|
| Mobile app | Flutter (Dart) — Android |
| On-device SMS analysis | Rule engine (Kotlin) + TinyBERT TFLite |
| Backend API | Flask (Python 3) + gunicorn |
| Cloud AI | gpt-oss-120b on Amazon Bedrock (OpenAI-compatible endpoint + SigV4 auth) |
| Risk scoring | Weighted multi-factor engine (backend + local mirror) |
| Backend DB | SQLite via Flask-SQLAlchemy |
| Backend hosting | Railway |

---

## Screens

| Screen | Purpose |
|--------|---------|
| Login | Mock OTP login; admin mode via `0000000000` |
| Home | Balance, quick actions, risk banner, admin demo controls |
| Send Money | 2-step flow: recipient → amount + numpad |
| Risk Warning | Factor breakdown, bar chart, checkbox confirmation |
| Critical Delay | 10-second countdown, risk factors, cancel / proceed |
| SMS Analysis | Device inbox scan, manual input, TinyBERT + cloud results |
| Transaction History | Search, filter chips, grouped list with risk tags |
| Profile Insights | Stats, frequent contacts, security summary |
| Payment Success | Animated confirmation, flag recipient option |

---

## Running the project

See [SETUP_INSTRUCTIONS.md](./SETUP_INSTRUCTIONS.md) for full first-time setup.

### Quick start (backend already hosted on Railway)

1. Install the APK from `frontend/build/app/outputs/flutter-apk/app-release.apk`
2. The app talks to the hosted backend automatically — no local server needed

### Local development

```powershell
# Terminal 1 — backend
cd backend
pip install -r requirements.txt
python app.py

# Terminal 2 — Flutter
cd frontend
flutter run
```

### Rebuild the APK

```powershell
cd frontend
flutter build apk --release
```

APK output: `frontend/build/app/outputs/flutter-apk/app-release.apk`

---

## Backend API

| Endpoint | Method | What it does |
|----------|--------|-------------|
| `/` | GET | Health check |
| `/status` | GET | Returns `cloud_configured` flag (used by admin UI) |
| `/risk-score` | POST | Scores a transaction (0–100) with factor breakdown |
| `/analyze-sms` | POST | Deep rule-based SMS fraud analysis |
| `/explain-risk` | POST | Human-readable explanation of risk factors |
| `/cloud-review` | POST | Escalates uncertain TinyBERT result to cloud LLM for second opinion |
| `/profile/transaction` | POST | Logs a completed transaction to the profile DB |
| `/profile/user/<upi_id>` | GET | Fetches risk tier for a recipient |
| `/profile/relationship` | GET | Fetches trust score between two UPI IDs |
| `/spam/flag` | POST | Community spam report |
| `/spam/check` | GET | Returns how many times a UPI ID has been flagged |

---

## Project structure

```
wallupi/
├── frontend/                        # Flutter app
│   ├── lib/
│   │   ├── main.dart
│   │   ├── theme/                   # Design system
│   │   ├── models/                  # Data models
│   │   ├── providers/               # AppProvider (state management)
│   │   ├── services/                # API, SMS bridge, risk engine, storage
│   │   ├── widgets/                 # Shared UI components
│   │   └── screens/                 # All app screens
│   └── android/
│       └── app/src/main/kotlin/com/example/wallupi/sms/
│           ├── RuleEngine.kt        # Tier 1 heuristics
│           ├── TinyBertTFLiteClassifier.kt  # Tier 2 on-device ML
│           └── SmsFraudDetector.kt  # Orchestrates all three tiers
├── backend/
│   ├── app.py                       # Flask entry point
│   ├── Procfile                     # gunicorn command for Railway
│   ├── runtime.txt                  # Python version pin
│   ├── requirements.txt
│   ├── .env                         # AWS credentials (gitignored)
│   └── routes/
│       ├── risk_score.py
│       ├── analyze_sms.py
│       ├── explain_risk.py
│       ├── cloud_sms_review.py      # Tier 3 — Bedrock LLM
│       └── profiles.py
└── SETUP_INSTRUCTIONS.md
```

---

## Admin mode

Login with phone `0000000000` and name `Kavy` to enter admin mode. This gives you:

- Pre-loaded demo transactions and SMS messages
- Demo controls panel on the home screen (simulate calls, toggle registered UPI)
- AI status indicators showing whether Cloud AI and TinyBERT are live
- Unlimited balance

---

## Demo scenarios

| What to do | Expected risk | Tier |
|------------|--------------|------|
| Send to `rahul@upi`, amount ≤ ₹1000 | ~10–15% | Safe |
| Send to new UPI ID, amount ₹8000 | ~55–65% | Soft warning |
| New recipient + enable "Simulate Call" | ~75–88% | Strong warning |
| New recipient + Unknown Caller + suspicious SMS | ~95%+ | Critical delay |
| SMS: "Your Aadhaar-linked account is frozen" (from numeric sender) | ~55%, Cloud Pending → ~70% after LLM | Cloud escalation example |

---

## Environment variables

`backend/.env` — never commit this file:

```
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_REGION=eu-north-1
AWS_DEFAULT_REGION=eu-north-1
BEDROCK_BASE_URL=https://bedrock-mantle.eu-north-1.api.aws/v1
BEDROCK_MODEL=openai.gpt-oss-120b
```

The Bedrock credentials must be scoped to the `bedrock-mantle` OpenAI-compatible endpoint (not standard `InvokeModel`). The IAM principal needs permission for this endpoint in the same region.

---

## Windows notes

```powershell
# Required once — prevents Git filename length errors
git config core.longpaths true
```

Never commit: `.env`, `*.apk`, `*.db`, `__pycache__/`, `.gradle-local/`
