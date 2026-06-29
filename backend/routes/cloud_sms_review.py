"""
Cloud SMS review endpoint — escalates uncertain TinyBERT detections to a cloud
LLM for a second opinion with an improved risk score and plain-English
explanation.

Cloud provider: Amazon Bedrock (OpenAI-compatible endpoint — bedrock-mantle)
Configured via environment variables (backend/.env):
    AWS_ACCESS_KEY_ID       — AWS access key
    AWS_SECRET_ACCESS_KEY   — AWS secret key
    AWS_SESSION_TOKEN       — (optional) for temporary credentials
    AWS_REGION              — AWS region (default: eu-north-1)
    BEDROCK_BASE_URL        — OpenAI-compatible base URL
    BEDROCK_MODEL           — model id (default: openai.gpt-oss-120b)
"""

import json
import os
import re

import boto3
import httpx
from botocore.auth import SigV4Auth as _SigV4Auth
from botocore.awsrequest import AWSRequest
from botocore.credentials import Credentials
from flask import Blueprint, jsonify, request
from openai import OpenAI

cloud_review_bp = Blueprint('cloud_review', __name__)

DEFAULT_BASE_URL = 'https://bedrock-mantle.eu-north-1.api.aws/v1'
DEFAULT_MODEL    = 'openai.gpt-oss-120b'
DEFAULT_REGION   = 'eu-north-1'

_VALID_CLASSIFICATIONS = {
    'safe', 'otp_theft', 'phishing', 'fake_kyc_verification',
    'upi_payment_fraud', 'social_engineering_scam',
    'apk_malware_link', 'fake_banking_alert',
}
_VALID_LEVELS = {'none', 'soft', 'strong', 'critical'}

_PROMPT_TEMPLATE = """You are a financial fraud detection expert analyzing SMS messages in India.

CONTEXT:
- SMS text (PII already sanitized by on-device engine): "{sanitized_body}"
- Sender: "{sender}"
- On-device rule engine flags: {flags}
- Local ML model risk score: {local_risk_pct}%
- Initial classification: "{classification}"
- Why cloud review was triggered: "{escalation_reason}"

The on-device TinyBERT model was uncertain about this message and needs a definitive second opinion.

Analyze the SMS for signs of:
- OTP / credential theft (asking for OTP, PIN, CVV, password)
- Phishing links (suspicious URLs, fake bank domains)
- Fake KYC / account verification scams
- UPI payment fraud (requests to send money to unknown UPI IDs)
- Social engineering (urgency, threats, too-good-to-be-true prizes)
- APK malware distribution links
- Fake banking alerts

Respond ONLY with valid JSON. No markdown fences, no extra text — just the JSON object:
{{
  "risk_score": <integer 0-100>,
  "classification": "<safe|otp_theft|phishing|fake_kyc_verification|upi_payment_fraud|social_engineering_scam|apk_malware_link|fake_banking_alert>",
  "intervention_level": "<none|soft|strong|critical>",
  "explanation": "<2-3 sentences in plain English explaining the key fraud indicators or why the message is safe>",
  "key_indicators": ["<concise indicator phrase>", "<concise indicator phrase>"],
  "confidence": <float 0.0-1.0>
}}"""


def _region() -> str:
    return (
        os.environ.get('AWS_REGION', '').strip()
        or os.environ.get('AWS_DEFAULT_REGION', '').strip()
        or DEFAULT_REGION
    )


def _base_url() -> str:
    return os.environ.get('BEDROCK_BASE_URL', '').strip() or DEFAULT_BASE_URL


def _model_id() -> str:
    return (
        os.environ.get('BEDROCK_MODEL', '').strip()
        or os.environ.get('BEDROCK_MODEL_ID', '').strip()
        or DEFAULT_MODEL
    )


def bedrock_ready() -> bool:
    """True when AWS credentials for Bedrock are present in the environment."""
    return bool(
        os.environ.get('AWS_ACCESS_KEY_ID', '').strip()
        and os.environ.get('AWS_SECRET_ACCESS_KEY', '').strip()
    )


class _BedrockSigV4Auth(httpx.Auth):
    """Signs outgoing httpx requests with AWS SigV4 for the Bedrock service.

    Only the stable headers (host, content-type, content-length) are included
    in the signed header set — the openai SDK adds extra x-stainless-* headers
    after signing which must be excluded from the canonical string to avoid
    signature mismatches.
    """

    def __init__(self, credentials, region: str):
        self._creds = credentials
        self._region = region

    def auth_flow(self, request):
        body = request.content
        sign_headers = {
            'host':           request.headers.get('host', ''),
            'content-type':   request.headers.get('content-type', 'application/json'),
            'content-length': str(len(body)),
        }
        if self._creds.token:
            sign_headers['x-amz-security-token'] = self._creds.token

        aws_req = AWSRequest(
            method=request.method.upper(),
            url=str(request.url),
            data=body,
            headers=sign_headers,
        )
        botocore_creds = Credentials(
            self._creds.access_key,
            self._creds.secret_key,
            self._creds.token,
        )
        _SigV4Auth(botocore_creds, 'bedrock', self._region).add_auth(aws_req)

        request.headers['Authorization'] = aws_req.headers['Authorization']
        request.headers['X-Amz-Date']    = aws_req.headers['X-Amz-Date']
        if self._creds.token:
            request.headers['X-Amz-Security-Token'] = self._creds.token
        yield request


_openai_client = None


def _get_client() -> OpenAI:
    """Lazily build (and cache) the OpenAI-compatible Bedrock client."""
    global _openai_client
    if _openai_client is None:
        session  = boto3.Session()
        frozen   = session.get_credentials().get_frozen_credentials()
        auth     = _BedrockSigV4Auth(frozen, _region())
        http_cli = httpx.Client(auth=auth, timeout=30.0)
        _openai_client = OpenAI(
            base_url=_base_url(),
            api_key='dummy',          # Required by SDK; auth is done via SigV4
            http_client=http_cli,
        )
    return _openai_client


def _extract_json(text: str) -> dict:
    """Extract JSON from the model response, stripping any markdown fences."""
    text = text.strip()
    text = re.sub(r'^```(?:json)?\s*', '', text, flags=re.IGNORECASE)
    text = re.sub(r'\s*```$', '', text)
    # Reasoning models prepend <reasoning>...</reasoning> — strip it.
    text = re.sub(r'<reasoning>.*?</reasoning>', '', text, flags=re.DOTALL | re.IGNORECASE)
    text = text.strip()
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        match = re.search(r'\{.*\}', text, re.DOTALL)
        if match:
            return json.loads(match.group(0))
        raise


def _validate_and_normalise(data: dict, local_risk_score: float) -> dict:
    """Validate model output and fill in safe defaults for missing/bad fields."""
    risk_score = data.get('risk_score', round(local_risk_score * 100))
    risk_score = max(0, min(100, int(risk_score)))

    classification = data.get('classification', 'safe')
    if classification not in _VALID_CLASSIFICATIONS:
        classification = 'social_engineering_scam' if risk_score >= 45 else 'safe'

    intervention_level = data.get('intervention_level', 'none')
    if intervention_level not in _VALID_LEVELS:
        if risk_score >= 95:
            intervention_level = 'critical'
        elif risk_score >= 80:
            intervention_level = 'strong'
        elif risk_score >= 50:
            intervention_level = 'soft'
        else:
            intervention_level = 'none'

    explanation = str(data.get('explanation', '')).strip()
    if not explanation:
        explanation = 'Cloud review could not generate an explanation.'

    key_indicators = data.get('key_indicators', [])
    if not isinstance(key_indicators, list):
        key_indicators = []
    key_indicators = [str(k) for k in key_indicators[:5]]

    confidence = float(data.get('confidence', 0.7))
    confidence = max(0.0, min(1.0, confidence))

    return {
        'risk_score':         risk_score,
        'classification':     classification,
        'intervention_level': intervention_level,
        'explanation':        explanation,
        'key_indicators':     key_indicators,
        'confidence':         confidence,
        'model_used':         _model_id(),
    }


def _invoke_model(prompt: str) -> str:
    """Call the Bedrock OpenAI-compatible endpoint and return the assistant text."""
    client = _get_client()
    response = client.chat.completions.create(
        model=_model_id(),
        messages=[
            {
                'role': 'system',
                'content': 'You are a financial fraud detection expert. Respond ONLY with valid JSON.',
            },
            {'role': 'user', 'content': prompt},
        ],
        max_tokens=1024,
        temperature=0.1,
    )
    choices = response.choices
    if not choices:
        return ''
    return (choices[0].message.content or '').strip()


@cloud_review_bp.route('/cloud-review', methods=['POST'])
def cloud_review():
    if not bedrock_ready():
        return jsonify({
            'error': 'Cloud review unavailable — AWS Bedrock credentials not configured'
        }), 503

    body = request.get_json(silent=True) or {}
    sanitized_body = str(body.get('sanitized_body', '')).strip()
    if not sanitized_body:
        return jsonify({'error': 'sanitized_body is required'}), 400

    local_risk_score  = float(body.get('local_risk_score', 0.0))
    classification    = str(body.get('classification', 'unknown'))
    sender            = str(body.get('sender', 'unknown'))
    flags             = body.get('flags', [])
    if not isinstance(flags, list):
        flags = []
    escalation_reason = str(body.get('escalation_reason', 'Model uncertainty'))

    prompt = _PROMPT_TEMPLATE.format(
        sanitized_body=sanitized_body,
        sender=sender,
        flags=', '.join(flags) if flags else 'none',
        local_risk_pct=round(local_risk_score * 100),
        classification=classification,
        escalation_reason=escalation_reason,
    )

    try:
        raw_text = _invoke_model(prompt)
        if not raw_text:
            return jsonify({'error': 'Cloud review returned an empty response'}), 503
        parsed = _extract_json(raw_text)
        result = _validate_and_normalise(parsed, local_risk_score)
        return jsonify(result), 200

    except json.JSONDecodeError as e:
        return jsonify({'error': f'Cloud model returned unparseable response: {e}'}), 503
    except Exception as e:
        return jsonify({'error': f'Cloud review failed: {str(e)}'}), 503
