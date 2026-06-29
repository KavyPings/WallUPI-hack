# Wallupi — Tasks

## ✅ Setup
- [x] Create Flutter setup instructions
- [x] Create Flutter project structure
- [x] Configure pubspec.yaml
- [x] Create Flask backend
- [x] Create requirements.txt
- [x] Create demo/mock data
- [x] Install backend dependencies
- [x] Test backend API endpoints

## ✅ Frontend — Design System
- [x] App theme (colors, typography, spacing)
- [x] Risk color helpers (green/yellow/red)
- [x] Gradients + shadows

## ✅ Frontend — Screens (9 total)
- [x] Login screen (mock OTP)
- [x] Home screen (balance, quick actions, bottom nav)
- [x] Send Money screen (QR scan + upload)
- [x] Risk Warning screen (chart, factors, checkbox)
- [x] Critical Delay screen (10s timer)
- [x] SMS Analysis screen (inbox + templates)
- [x] Profile Insights screen (stats, pie chart)
- [x] Transaction History screen
- [x] Payment Success screen

## ✅ Frontend — Services
- [x] SMS detector (on-device rule-based)
- [x] API service (with offline fallback)
- [x] Storage service (SharedPreferences)
- [x] App Provider (state management)

## ✅ Backend — Flask
- [x] app.py (CORS, blueprints)
- [x] /analyze-sms (8 keyword categories)
- [x] /risk-score (4 weighted categories)
- [x] /explain-risk (template explanations)

## ✅ AI Logic
- [x] Keyword-based SMS fraud detection
- [x] Weighted risk scoring engine
- [x] Template-based explanations
- [x] Call-state risk boost

## ✅ Integration
- [x] Frontend ↔ Backend API connection
- [x] Offline fallback logic
- [x] SMS → Risk → Intervention flow
- [x] QR scan + upload dual mode
- [x] Demo controls (call state toggle)

## ⏳ Testing (Requires Flutter SDK)
- [ ] flutter pub get
- [ ] flutter run on emulator
- [ ] flutter run on physical device
- [ ] Test Flow 1: Normal payment
- [ ] Test Flow 2: Fraud detection warning
- [ ] Test Flow 3: Critical fraud delay
