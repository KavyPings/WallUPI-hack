# WallUPI — Technical Documentation

**An AI-powered, real-time fraud firewall for UPI payments.**
Flutter (Android) · on-device Kotlin AI · Flask backend · Amazon Bedrock (gpt-oss-120b)

> WallUPI is a mock UPI payment app with a real fraud-detection core. Every payment is scored *before* money can leave the account, and every SMS in the inbox is classified through a three-tier AI pipeline. No real money moves — but the detection logic underneath is production-grade.

This document is organized around the six evaluation criteria: **Technical Implementation, Innovation & Creativity, User Experience & Usability, Scalability & Architecture, Problem–Solution Fit, and Overall Presentation Quality.**

---

## 1. The essence in one paragraph

Today's payment apps validate the *transaction* — is the UPI ID valid, is the balance sufficient, is the PIN correct. None of them validate the *situation*: are you on a call with a stranger right now, did a scam SMS just arrive naming this exact payee, have you ever paid this person before, did a QR or link drop you here. WallUPI reads that human context, fuses it into a single transparent **risk score (0–100)**, and applies **proportional friction** — from a silent pass to a forced 10-second lock — at the precise moment a scam depends on speed and pressure.

---

## 2. Tech stack

| Layer | Technology |
|-------|-----------|
| Mobile app | **Flutter (Dart)** — Android; Provider state management |
| On-device fraud AI | **Kotlin** rule engine + **TinyBERT** quantized model via **TensorFlow Lite** (XNNPACK) |
| Native bridges | Android `MethodChannel`s for SMS, telephony/call-state, and payment-origin |
| Backend API | **Flask (Python 3)** + Flask-SQLAlchemy, served by **gunicorn** |
| Cloud AI | **gpt-oss-120b on Amazon Bedrock** via the OpenAI-compatible `bedrock-mantle` endpoint, authenticated with **AWS SigV4** |
| Database | **SQLite** (Flask-SQLAlchemy ORM) for community intelligence |
| Hosting | **Railway** (backend); APK distributed directly |
| Key Flutter packages | `provider`, `fl_chart`, `mobile_scanner` (QR), `google_fonts`, `shared_preferences`, `http`, `percent_indicator`, `animations`, `shimmer` |
| Key backend packages | `flask`, `flask-sqlalchemy`, `flask-cors`, `boto3`/`botocore`, `openai`, `httpx`, `gunicorn` |

---

## 3. Technical Implementation

### 3.1 Three-tier SMS fraud detection

Every message is processed through layers in sequence, escalating only when needed:

**Tier 1 — Rule Engine** (`RuleEngine.kt`, on-device, ~1 ms, fully offline)
Heuristic scoring over keyword categories, sender patterns, URL analysis (shortened links, `.apk` payloads, look-alike domains on suspicious TLDs), call-to-action phrasing, and compound multipliers. Maintains a **trusted-domain allowlist** (banks, NPCI, telecom, gov, big tech) so legitimate links aren't falsely flagged. Scores **> 0.85** short-circuit as obvious scams; **< 0.15** short-circuit as obviously safe; the uncertain middle escalates.

**Tier 2 — TinyBERT** (`TinyBertTFLiteClassifier.kt`, on-device TFLite, ~50 ms)
A quantized BERT classifier with its own tokenizer (`TinyBertTokenizer.kt`) categorizes SMS into fraud classes: OTP theft, phishing, fake KYC, UPI fraud, social engineering, APK malware, fake banking alert. The model is **additive only** — a universal rule-score floor prevents TinyBERT from *lowering* a score the rule engine already established from hard evidence.

**Tier 3 — Cloud LLM** (`cloud_sms_review.py`, gpt-oss-120b on Bedrock, ~2–5 s)
Escalation fires when any of these hold *and* combined risk ≥ 55%:
- TinyBERT confidence is below threshold (it's unsure), or
- TinyBERT says **safe ≥ 80%** while the rule engine scores **≥ 45%** — the disagreement (`modelDisagreesWithRules`) is itself treated as a signal, or
- the model file is unavailable on the device.

A **PII-sanitized** copy of the SMS is sent to the LLM, which returns a refined score, classification, intervention level, plain-English explanation, key indicators, and confidence. The result updates the on-screen "Cloud AI Review" card.

### 3.2 Transaction risk engine

`risk_score.py` (backend) and `risk_decision_engine.dart` (on-device mirror) compute a weighted suspicion score from four factor groups:

| Group | Weight | Example factors |
|-------|:------:|-----------------|
| User profile | 25% | amount anomaly vs personal average, very large amount, unusual time |
| Recipient profile | 30% | new recipient, individual-not-merchant, low trust, community-flagged, high-risk profile |
| Relationship | 20% | limited history, unusual amount for this payee, prior flagged transactions |
| Context | 25% | suspicious SMS, active/unknown call, QR or external-link origin, sudden navigation |

The weighted sum is normalized to 0–100, then refined by several intelligence layers:

- **SMS correlation intelligence** — a generic KYC scam SMS on the device adds only ambient risk (~8%), but if the suspicious SMS's *sender matches the payee* (strongest signal) or the payee's UPI/name/amount appears in the SMS body, the penalty scales up sharply (up to ~45%).
- **Relationship trust reduction** — trusted recipients (transaction count, trust score, verified merchant) earn a score *reduction*; correlated-SMS evidence halves that protection so a "known" payee still triggers a warning when explicitly named in a scam.
- **Compound danger overrides** — unambiguous patterns (active call + correlated SMS + new recipient) hard-floor the score to 95–97, because the capped weighting can't otherwise capture textbook social-engineering combinations.
- **Registered UPI Business dampener** — an NPCI-registered payee halves the final score (systemic accountability).

### 3.3 Four-tier proportional intervention

| Score | Tier | Behaviour |
|:-----:|------|-----------|
| 0–49 | Safe | Goes through instantly |
| 50–79 | Soft | Review popup listing the specific risk factors |
| 80–94 | Strong | Full warning screen + mandatory acknowledgement checkbox |
| 95–100 | Critical | **10-second forced lock** + checkbox before proceeding |

Thresholds are defined once and **mirrored** between backend (`risk_score.py`) and client (`RiskThresholds`), so routing is deterministic and consistent whether scored online or offline.

### 3.4 Backend API

| Endpoint | Method | Purpose |
|----------|:------:|---------|
| `/` , `/status` | GET | Health check; reports `cloud_configured` for admin UI |
| `/risk-score` | POST | Weighted transaction score with factor breakdown |
| `/analyze-sms` | POST | Deep rule-based SMS analysis |
| `/explain-risk` | POST | Human-readable risk explanation |
| `/cloud-review` | POST | Escalate uncertain TinyBERT result to the cloud LLM |
| `/profile/transaction` | POST | Log a completed transaction |
| `/profile/user/<upi_id>` | GET | Recipient risk tier |
| `/profile/relationship` | GET | Trust score between two UPI IDs |
| `/spam/flag` , `/spam/check` | POST/GET | Community spam reporting & lookup |

### 3.5 Testing

The fraud logic is unit-tested independently of the UI: a backend pytest suite plus Kotlin unit tests for the rule engine, PII sanitizer, fraud-detector orchestration, and tokenizer, alongside an instrumented on-device TinyBERT test. The deterministic scoring core makes behaviour reproducible and demo-stable.

---

## 4. Innovation & Creativity

- **Context over content.** The first UPI layer to fuse *call state + SMS inbox + recipient history + payment origin* into one score, instead of judging the transaction in isolation.
- **Time as the intervention.** The 10-second critical lock is the product, not a bug — it directly attacks the time-pressure that every "stay-on-the-line" scam relies on.
- **Disagreement as signal.** When the on-device model and the rule engine *contradict each other*, that conflict itself triggers cloud escalation — uncertainty is treated as information.
- **Sender-match detection.** Recognizing that the number that *sent* the scam SMS is the same number you're about to *pay* is the single strongest fraud signal — and WallUPI models it explicitly.
- **Payment-origin awareness.** `PaymentOriginDetector.kt` reads the Android referrer to know whether a payment was launched from a browser, WhatsApp, or another app — catching phishing flows at their entry point, not just their destination.
- **Privacy as architecture.** A dedicated `SanitizationEngine` strips phone numbers, OTPs, account/card/Aadhaar/PAN numbers, UPI PINs, emails, and names *before* anything reaches the cloud.

---

## 5. User Experience & Usability

- **Familiar by design.** Looks and flows like Google Pay / PhonePe — balance, contacts, a two-step send flow — so there's zero learning curve. Protection is invisible until it's needed.
- **Proportional friction.** Low-risk payments are untouched; friction appears only in proportion to danger, so the system stays trustworthy and non-annoying.
- **Transparent, not paternalistic.** Every warning shows *exactly why* — a ranked factor breakdown and a bar chart (`fl_chart`), never a generic "this looks risky."
- **Real-time protection.** A background `SmsReceiver` analyzes incoming messages as they arrive and raises a `ScamNotifier` alert; the inbox auto-scans on open.
- **Resilience built in.** If the backend is unreachable, the on-device engine mirrors scoring, and an **Offline Payment** path (USSD `*99#`, 123PAY IVR, or in-app) keeps the full fraud layer running without a data connection.
- **Demo-ready.** An admin mode (`0000000000` / `Kavy`) preloads realistic transactions and scam SMS and exposes toggles (simulate call, unknown caller, registered UPI) to walk through every risk tier live.

**Screens:** Login · Home · Send Money · Risk Warning · Critical Delay · SMS Analysis · Transaction History · Profile Insights · Payment Success · QR Scanner · Offline Payment picker.

---

## 6. Scalability & Architecture

- **On-device first, cloud by exception.** Tiers 1–2 and the risk mirror run locally with no network; the cloud LLM is invoked only for genuinely uncertain cases, keeping cost, latency, and data exposure minimal — and the model improving without re-shipping the app.
- **Stateless, modular backend.** Flask **blueprints** per concern (`risk_score`, `analyze_sms`, `explain_risk`, `cloud_sms_review`, `profiles`, `otp`) behind gunicorn scale horizontally; SQLite via SQLAlchemy is a drop-in swap to Postgres for production volume.
- **Graceful degradation everywhere.** Community-data lookups, model loading, and cloud calls all fail safe to sensible defaults — the app never blocks on an unavailable dependency.
- **Community intelligence that compounds.** `UserProfile` (risk tiers), `RelationshipProfile` (trust scores), and `SpamFlag` (crowd reports) mean every flagged fraudster improves protection for all users — a network effect that scales with adoption.
- **Single source of truth.** Thresholds and weights are centralized and mirrored client/server, so behaviour is consistent and tunable from one place.
- **Performance-tuned inference.** TinyBERT runs via TFLite with multi-threading and XNNPACK, loaded lazily and thread-safely once per process.

---

## 7. Problem–Solution Fit

UPI fraud in India costs thousands of crores a year, and nearly all of it follows one script: a panic SMS → a caller impersonating a bank or officer → being walked through a payment with no time to think → an irreversible transfer. The script works not because victims are careless, but because it's **fast, pressured, and unsupervised.**

WallUPI is built precisely against that script. It watches the exact signals the scam needs — the live call, the panic SMS, the unfamiliar payee, the rushed navigation — and inserts the one thing the scammer cannot allow: **a pause, with a reason.** It targets the most-victimized and least-defended users (first-time and elderly payers) while staying adoptable at national scale because protection runs on-device and privacy-first.

---

## 8. What it does differently from the market

| | GPay / PhonePe / Paytm | **WallUPI** |
|---|---|---|
| What's validated | The transaction (ID, balance, PIN) | The **situation** around the transaction |
| Signals used | Payee + amount | Payee history **+ SMS + call state + payment origin**, fused |
| Response to risk | Binary allow / block | **Proportional friction** across four tiers |
| Scam SMS ↔ payee link | None | **Sender / body correlation** detection |
| Time pressure | Not addressed | **Forced 10-second cool-off** at critical risk |
| Privacy of analysis | — | **On-device**, PII sanitized before any cloud call |
| Offline fraud checks | — | Full fraud layer over **USSD / IVR** |
| Crowd intelligence | — | **Community spam flags** + shared trust scores |

---

## 9. Overall status

A working end-to-end prototype: Flutter app + hosted Flask backend, a live five-signal risk engine, the full three-tier SMS pipeline (rules + TinyBERT + Bedrock), community spam intelligence, shipped phishing-origin payment detection, and a working offline-UPI path — all backed by a deterministic, unit-tested scoring core.

---

*Team Red Dead Codemption — Kavy Khilrani · Arhan Sapra · Aditya Srivastava*
