"""
OTP send / verify endpoints.

Fixed OTP 123456 for demo purposes.
"""

from flask import Blueprint, jsonify, request

otp_bp = Blueprint('otp', __name__)

_pending: set[str] = set()


@otp_bp.route('/otp/send', methods=['POST'])
def send_otp():
    body = request.get_json(silent=True) or {}
    phone = str(body.get('phone', '')).strip()
    if not phone.isdigit() or len(phone) != 10:
        return jsonify({'error': 'phone must be a 10-digit number'}), 400
    _pending.add(phone)
    return jsonify({'message': f'OTP sent to +91-{phone}'}), 200


@otp_bp.route('/otp/verify', methods=['POST'])
def verify_otp():
    body = request.get_json(silent=True) or {}
    phone = str(body.get('phone', '')).strip()
    entered = str(body.get('otp', '')).strip()
    if phone not in _pending:
        return jsonify({'error': 'OTP not requested. Please request one first.'}), 400
    if entered != '123456':
        return jsonify({'error': 'Incorrect OTP'}), 400
    _pending.discard(phone)
    return jsonify({'message': 'verified'}), 200
