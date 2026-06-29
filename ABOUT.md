# About Wallupi

## What is it?

Wallupi is a payment app — like Google Pay or PhonePe — but with one extra superpower: **it tries to catch you before you get scammed.**

Every time you try to send money, Wallupi quietly runs a background check on the transaction. If something looks suspicious, it slows you down, shows you exactly why it's concerned, and asks you to think twice before proceeding.

It is a mock app, meaning no real money moves. But the fraud detection underneath it is real — the same logic that would protect you in a live payment scenario.

---

## What problem does it solve?

UPI scams in India are exploding. The most common ones work like this:

- You get an SMS saying your bank account is about to be blocked. You panic.
- Someone calls you pretending to be a bank employee or government officer.
- They walk you through sending money to "verify your account" or "unfreeze your funds."
- The money is gone the moment you confirm.

The tragedy is that these scams work not because people are careless, but because they happen fast, under pressure, and the victim has no one in their corner pointing out the warning signs.

Wallupi is that voice in the corner.

---

## How does it actually work?

When you tap "Send Money," Wallupi checks five things simultaneously:

**1. Who are you sending to?**
Have you sent to this person before? How many times? Have other Wallupi users reported this UPI ID as suspicious? A brand-new recipient you've never paid before carries more risk than someone you pay every month.

**2. Is the amount normal?**
Wallupi learns your average transaction size. Sending 10x your usual amount to a new contact is a red flag — even if everything else looks fine.

**3. Are you on a phone call right now?**
This is one of the biggest indicators of a live scam. Fraudsters stay on the line and keep talking while you complete the payment, so you don't have time to think. Wallupi detects active calls and raises the alert level significantly.

**4. Did you get a suspicious SMS recently?**
Wallupi reads your SMS inbox (with your permission) and runs each message through an AI model that looks for scam patterns — fake KYC alerts, lottery wins, OTP theft attempts, fake banking messages. If a suspicious SMS arrived recently and the payment recipient's number appears in that message, that is treated as a serious warning signal.

**5. How did you arrive at this payment screen?**
Did you scan a QR code? Follow a link? These are higher-risk entry points than manually typing a UPI ID, because a scammer can hand you a fake QR code or send you a phishing link.

---

## What is a "risk score"?

All five checks feed into a single number between 0 and 100. Think of it as a suspicion meter.

- **0–49:** Green zone. The payment looks normal. It goes through without interruption.
- **50–79:** Yellow zone. Something is a little off — maybe it's a first-time recipient and a medium-large amount. Wallupi shows you a warning card listing the specific reasons.
- **80–94:** Orange zone. Multiple risk factors are present at once. Wallupi shows a full warning screen. You have to tick a checkbox acknowledging the risks before you can proceed.
- **95–100:** Red zone. This looks like an active scam scenario. Wallupi pauses the transaction for **10 seconds** — you physically cannot proceed during that time. After the countdown, you must still confirm before the payment goes through.

The 10-second pause is intentional. Research shows that even a brief forced pause breaks the psychological pressure that scammers create. It gives you time to hang up the phone, re-read the SMS, and question whether this payment makes sense.

---

## What AI is involved?

Wallupi has three layers of AI working together:

**Layer 1 — On-device rules (always running)**
A set of hand-crafted rules that run entirely on your phone. No internet required. These catch the obvious patterns: words like "urgent," "OTP," "KYC expired," requests to "send money now," fake government impersonation, etc.

**Layer 2 — TinyBERT (on-device machine learning)**
A small but capable language model that runs locally on Android. It reads SMS messages and classifies them into fraud categories: OTP theft, phishing, fake KYC, UPI fraud, social engineering, and more. It is fast, private, and works offline.

**Layer 3 — gpt-oss-120b on Amazon Bedrock (cloud AI)**
When TinyBERT is not confident about a message — it detected something suspicious but isn't sure how serious — it sends a sanitized (personal details removed) version of the SMS to a large language model (gpt-oss-120b, hosted on Amazon Bedrock) for a second opinion. The cloud model returns a detailed explanation of what it found and why, in plain English.

All three layers run in parallel. The results are combined into the final risk score.

---

## What happens to my data?

- Your SMS messages are analyzed on your device. Only sanitized, anonymous snippets are ever sent to the cloud — your name, account numbers, and phone numbers are stripped out before anything leaves your phone.
- Transaction history is stored locally on your device.
- Community spam reports (when you flag a UPI ID as suspicious) are stored on the backend so other users benefit from your report.

---

## Who is it for?

Wallupi was built as a demonstration of what proactive fraud prevention could look like if it were built into payment apps by default.

It is useful for:

- **Demonstrations and presentations** — showing how AI can be applied to financial safety
- **Research and education** — understanding how UPI scams work and how technology can counter them
- **Testing fraud detection logic** — the admin mode lets you simulate different risk scenarios and see how the system responds

It is not a live banking app. No real money is involved.

---

## The admin mode

There is a special login for testing all the fraud scenarios without needing to actually be in a scam situation. Log in with phone number `0000000000` and name `Kavy`. This gives you:

- A pre-loaded set of realistic demo transactions
- Pre-loaded suspicious SMS messages in the inbox
- Toggles on the home screen to simulate being on a phone call, or being called by an unknown number
- Indicators showing whether Cloud AI and TinyBERT are currently active
- Unlimited balance for testing any amount

---

## One sentence summary

Wallupi is an AI-powered safety layer for UPI payments that detects scams in real time — using your SMS inbox, call state, and transaction history — and slows you down before you can send money to a fraudster.
