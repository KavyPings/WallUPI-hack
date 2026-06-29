# Wallupi — Setup Instructions

Complete guide for setting up the project from scratch on Windows.

---

## For end users (just want to run the app)

1. **Install the APK** on your Android phone
   - Get `frontend/build/app/outputs/flutter-apk/app-release.apk`
   - Transfer via USB, WhatsApp, or Google Drive
   - Tap to install (allow "Install from unknown sources" if prompted)

2. The app connects to the hosted backend automatically. No local server needed.

---

## For developers (full setup)

### What you need

| Tool | Version | Check |
|------|---------|-------|
| Python | 3.10+ | `python --version` |
| Flutter SDK | 3.x | `flutter --version` |
| Android Studio | Latest | For emulator / SDK tools |
| Git | Any | `git --version` |

---

### Step 1 — Clone and configure

```powershell
git clone https://github.com/arhansaps/wallupi.git
cd wallupi
git config core.longpaths true
```

---

### Step 2 — Backend setup (local dev)

**Install dependencies:**

```powershell
cd backend
pip install -r requirements.txt
```

**Create the environment file:**

Create `backend/.env` (this file is gitignored — never commit it):

```
AWS_ACCESS_KEY_ID=your_access_key
AWS_SECRET_ACCESS_KEY=your_secret_key
AWS_REGION=eu-north-1
AWS_DEFAULT_REGION=eu-north-1
BEDROCK_BASE_URL=https://bedrock-mantle.eu-north-1.api.aws/v1
BEDROCK_MODEL=openai.gpt-oss-120b
```

> **Note:** The credentials must be scoped for the `bedrock-mantle` OpenAI-compatible endpoint, not the standard boto3 `InvokeModel` API. These are different access paths. The region must match where your Bedrock access is provisioned.

**Verify the backend starts:**

```powershell
python app.py
```

You should see: `Wallupi Backend running on http://0.0.0.0:5000`

Open `http://localhost:5000` in a browser — you should get a JSON health response.

---

### Step 3 — Host the backend on Railway (for real device / always-on)

Railway is the recommended hosting path for sharing with others or demoing on a physical device.

1. Go to [railway.app](https://railway.app) → **New Project** → **Deploy from GitHub repo**
2. Select the `wallupi` repo
3. Set **Root Directory** to `backend`
4. Railway will auto-detect Python and run gunicorn via the `Procfile`
5. Go to the **Variables** tab and add:

   | Key | Value |
   |-----|-------|
   | `AWS_ACCESS_KEY_ID` | your key |
   | `AWS_SECRET_ACCESS_KEY` | your secret |
   | `AWS_REGION` | `eu-north-1` |
   | `AWS_DEFAULT_REGION` | `eu-north-1` |
   | `BEDROCK_BASE_URL` | `https://bedrock-mantle.eu-north-1.api.aws/v1` |
   | `BEDROCK_MODEL` | `openai.gpt-oss-120b` |

6. Railway gives you a public URL like `https://wallupi-backend-production.up.railway.app`

---

### Step 4 — Set the backend URL in the Flutter app

The backend URL lives in one place:

```
frontend/lib/services/api_service.dart  →  static const String _baseUrl
```

| Scenario | URL to use |
|----------|-----------|
| Railway (real device, always-on) | `https://your-project.up.railway.app` |
| Android emulator (local dev) | `http://10.0.2.2:5000` |
| Physical device on same WiFi | `http://192.168.x.x:5000` |

Change the value and rebuild the APK after any URL change.

---

### Step 5 — Flutter setup

**Install Flutter SDK** (if not already installed):

1. Download from [flutter.dev](https://docs.flutter.dev/get-started/install/windows/mobile)
2. Extract to `C:\flutter` (path must have no spaces)
3. Add `C:\flutter\bin` to your system PATH:
   - Start Menu → "Environment Variables" → User variables → Path → New → `C:\flutter\bin`
4. Restart your terminal

**Verify:**

```powershell
flutter doctor
```

**Accept Android licenses:**

```powershell
flutter doctor --android-licenses
```

**Get Flutter dependencies:**

```powershell
cd frontend
flutter pub get
```

---

### Step 6 — Build the APK

```powershell
cd frontend
flutter build apk --release
```

APK will be at:
```
frontend/build/app/outputs/flutter-apk/app-release.apk
```

Transfer to your phone via USB, WhatsApp, or Google Drive and install.

Subsequent builds use Gradle's incremental cache and finish in ~1–2 minutes.

---

### Step 7 — Install on your phone

1. On your Android phone: Settings → Apps → Special app access → Install unknown apps → enable for your file manager or browser
2. Transfer the APK and tap to install
3. Or via ADB (if USB debugging is enabled): `adb install app-release.apk`

---

## Running in development (hot reload)

```powershell
# Terminal 1 — start local backend
cd backend
python app.py

# Terminal 2 — run Flutter on a connected device or emulator
cd frontend
flutter run
```

Make sure a device or emulator is connected (`flutter devices` to check).

---

## Android emulator setup (optional)

1. Open Android Studio → More Actions → Virtual Device Manager
2. Create Device → Pixel 6 → API 34 → Finish
3. Start the emulator
4. Set `_baseUrl` in `api_service.dart` to `http://10.0.2.2:5000` for emulator-to-host loopback

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `flutter` not found | Restart terminal after adding to PATH |
| No devices found | Start emulator or enable USB debugging on phone |
| Android licenses error | Run `flutter doctor --android-licenses` |
| Gradle build fails | Open Android Studio → SDK Manager → install missing tools |
| Git filename too long | `git config core.longpaths true` |
| App shows no backend data | Check Railway deployment is running; verify URL in `api_service.dart` |
| Cloud AI light stays off | Check Railway env vars are set correctly and Bedrock access is provisioned in `eu-north-1` |
| TinyBERT light stays off | Model file not bundled — app falls back to rule engine only (normal behaviour) |
| Cloud review returns 401 | SigV4 region mismatch — ensure `AWS_REGION=eu-north-1`, not `us-west-2` |
| Cloud review returns 503 | `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY` missing from Railway variables |
| APK connects to wrong server | `_baseUrl` in `api_service.dart` still set to `10.0.2.2:5000` — update and rebuild |

---

## Project secrets (never commit)

| File | Contains |
|------|---------|
| `backend/.env` | AWS Bedrock credentials |

This file is listed in `.gitignore` and will not be tracked by Git. Set the same values as Railway environment variables for hosted deployments.
