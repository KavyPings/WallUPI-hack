Drop the production TinyBERT artifacts into this folder using these exact names:

- tinybert_sms_classifier.tflite
- tinybert_vocab.txt

The Kotlin integration already handles:
- WordPiece tokenization
- TensorFlow Lite interpreter loading
- Rule engine pre-filtering
- Risk scoring
- Sensitive-data sanitization before future cloud escalation

If the model or vocab is missing, the app falls back to rule-only local detection.
