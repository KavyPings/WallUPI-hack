from datetime import datetime, timedelta, timezone

from flask import Blueprint, jsonify, request

from database import db
from models import RelationshipProfile, SpamFlag, TransactionLog, UserProfile

profiles_bp = Blueprint('profiles', __name__)


def _upsert_user_profile(upi_id: str, risk_score: int, is_merchant: bool = False) -> UserProfile:
    profile = db.session.get(UserProfile, upi_id)
    if profile is None:
        profile = UserProfile(
            upi_id=upi_id,
            account_type='merchant' if is_merchant else 'individual',
            total_txn_count=0,
            high_risk_txn_count=0,
            flagged_by_others_count=0,
            risk_tier='low',
        )
        db.session.add(profile)
        db.session.flush()  # materialize defaults before incrementing
    profile.total_txn_count += 1
    if risk_score >= 80:
        profile.high_risk_txn_count += 1
    profile.recompute_risk_tier()
    return profile


def _upsert_relationship(user_upi: str, counterpart_upi: str, amount: float, risk_score: int) -> RelationshipProfile:
    rel = RelationshipProfile.query.filter_by(
        user_upi_id=user_upi,
        counterpart_upi_id=counterpart_upi,
    ).first()
    if rel is None:
        rel = RelationshipProfile(
            user_upi_id=user_upi,
            counterpart_upi_id=counterpart_upi,
            txn_count=0,
            total_amount=0.0,
            avg_amount=0.0,
            flagged_txn_count=0,
            trust_score=50,
        )
        db.session.add(rel)
        db.session.flush()  # materialize defaults before incrementing
    rel.txn_count += 1
    rel.total_amount += amount
    rel.avg_amount = rel.total_amount / rel.txn_count
    if risk_score >= 80:
        rel.flagged_txn_count += 1
    rel.last_txn_at = datetime.now(timezone.utc)
    rel.recompute_trust_score()
    return rel


@profiles_bp.route('/profile/transaction', methods=['POST'])
def log_transaction():
    data = request.get_json(silent=True) or {}
    user_upi = data.get('user_upi_id', '').strip()
    recipient_upi = data.get('recipient_upi_id', '').strip()
    amount = float(data.get('amount', 0))
    risk_score = int(data.get('risk_score', 0))
    intervention_level = data.get('intervention_level', 'none')
    is_merchant = bool(data.get('is_merchant', False))

    if not user_upi or not recipient_upi:
        return jsonify({'error': 'user_upi_id and recipient_upi_id are required'}), 400

    log = TransactionLog(
        user_upi_id=user_upi,
        recipient_upi_id=recipient_upi,
        amount=amount,
        risk_score=risk_score,
        intervention_level=intervention_level,
    )
    db.session.add(log)
    _upsert_user_profile(recipient_upi, risk_score, is_merchant)
    _upsert_relationship(user_upi, recipient_upi, amount, risk_score)
    db.session.commit()

    return jsonify({'status': 'ok'}), 201


@profiles_bp.route('/spam/flag', methods=['POST'])
def flag_spam():
    data = request.get_json(silent=True) or {}
    reporter = data.get('reporter_upi_id', '').strip()
    flagged_upi = data.get('flagged_upi_id', '').strip() or None
    flagged_phone = data.get('flagged_phone', '').strip() or None
    reason = data.get('reason', 'spam').strip()
    note = data.get('note', '').strip() or None

    if not reporter:
        return jsonify({'error': 'reporter_upi_id is required'}), 400
    if not flagged_upi and not flagged_phone:
        return jsonify({'error': 'flagged_upi_id or flagged_phone is required'}), 400

    # Deduplicate: same reporter + same target within 7 days
    one_week_ago = datetime.now(timezone.utc) - timedelta(days=7)
    existing = SpamFlag.query.filter(
        SpamFlag.reporter_upi_id == reporter,
        SpamFlag.flagged_upi_id == flagged_upi,
        SpamFlag.flagged_phone == flagged_phone,
        SpamFlag.created_at >= one_week_ago,
    ).first()
    if existing:
        return jsonify({'status': 'already_flagged'}), 200

    flag = SpamFlag(
        reporter_upi_id=reporter,
        flagged_upi_id=flagged_upi,
        flagged_phone=flagged_phone,
        reason=reason,
        note=note,
    )
    db.session.add(flag)

    # Increment flagged_by_others_count on the target's UserProfile
    if flagged_upi:
        profile = db.session.get(UserProfile, flagged_upi)
        if profile is None:
            profile = UserProfile(
                upi_id=flagged_upi,
                total_txn_count=0,
                high_risk_txn_count=0,
                flagged_by_others_count=0,
                risk_tier='low',
            )
            db.session.add(profile)
        profile.flagged_by_others_count += 1
        profile.recompute_risk_tier()

    db.session.commit()
    return jsonify({'status': 'flagged'}), 201


@profiles_bp.route('/spam/check', methods=['GET'])
def check_spam():
    upi_id = request.args.get('upi_id', '').strip() or None
    phone = request.args.get('phone', '').strip() or None

    if not upi_id and not phone:
        return jsonify({'flag_count': 0, 'is_flagged': False, 'reasons': []}), 200

    query = SpamFlag.query
    if upi_id and phone:
        query = query.filter(
            (SpamFlag.flagged_upi_id == upi_id) | (SpamFlag.flagged_phone == phone)
        )
    elif upi_id:
        query = query.filter(SpamFlag.flagged_upi_id == upi_id)
    else:
        query = query.filter(SpamFlag.flagged_phone == phone)

    flags = query.all()
    reasons = list({f.reason for f in flags})
    return jsonify({
        'flag_count': len(flags),
        'is_flagged': len(flags) > 0,
        'reasons': reasons,
    }), 200


@profiles_bp.route('/profile/user/<upi_id>', methods=['GET'])
def get_user_profile(upi_id: str):
    profile = db.session.get(UserProfile, upi_id)
    if profile is None:
        return jsonify({'error': 'not found'}), 404
    return jsonify(profile.to_dict()), 200


@profiles_bp.route('/profile/relationship', methods=['GET'])
def get_relationship():
    user_upi = request.args.get('user_upi', '').strip()
    counterpart_upi = request.args.get('counterpart_upi', '').strip()
    if not user_upi or not counterpart_upi:
        return jsonify({'error': 'user_upi and counterpart_upi are required'}), 400
    rel = RelationshipProfile.query.filter_by(
        user_upi_id=user_upi,
        counterpart_upi_id=counterpart_upi,
    ).first()
    if rel is None:
        return jsonify({'error': 'not found'}), 404
    return jsonify(rel.to_dict()), 200
