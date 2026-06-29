from datetime import datetime, timezone

from sqlalchemy import CheckConstraint, UniqueConstraint

from database import db


def _utcnow():
    return datetime.now(timezone.utc)


class UserProfile(db.Model):
    __tablename__ = 'user_profiles'

    upi_id = db.Column(db.String, primary_key=True)
    account_type = db.Column(db.String, default='individual')  # 'individual' | 'merchant'
    total_txn_count = db.Column(db.Integer, default=0)
    high_risk_txn_count = db.Column(db.Integer, default=0)
    flagged_by_others_count = db.Column(db.Integer, default=0)
    risk_tier = db.Column(db.String, default='low')  # 'low' | 'medium' | 'high'
    created_at = db.Column(db.DateTime, default=_utcnow)
    updated_at = db.Column(db.DateTime, default=_utcnow, onupdate=_utcnow)

    def recompute_risk_tier(self):
        ratio = self.high_risk_txn_count / self.total_txn_count if self.total_txn_count > 0 else 0
        if ratio > 0.4 or self.flagged_by_others_count >= 5:
            self.risk_tier = 'high'
        elif ratio > 0.15 or self.flagged_by_others_count >= 2:
            self.risk_tier = 'medium'
        else:
            self.risk_tier = 'low'

    def to_dict(self):
        return {
            'upi_id': self.upi_id,
            'account_type': self.account_type,
            'total_txn_count': self.total_txn_count,
            'high_risk_txn_count': self.high_risk_txn_count,
            'flagged_by_others_count': self.flagged_by_others_count,
            'risk_tier': self.risk_tier,
            'created_at': self.created_at.isoformat() if self.created_at else None,
            'updated_at': self.updated_at.isoformat() if self.updated_at else None,
        }


class RelationshipProfile(db.Model):
    __tablename__ = 'relationship_profiles'
    __table_args__ = (UniqueConstraint('user_upi_id', 'counterpart_upi_id'),)

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    user_upi_id = db.Column(db.String, nullable=False)
    counterpart_upi_id = db.Column(db.String, nullable=False)
    txn_count = db.Column(db.Integer, default=0)
    total_amount = db.Column(db.Float, default=0.0)
    avg_amount = db.Column(db.Float, default=0.0)
    flagged_txn_count = db.Column(db.Integer, default=0)
    trust_score = db.Column(db.Integer, default=50)
    last_txn_at = db.Column(db.DateTime, nullable=True)
    created_at = db.Column(db.DateTime, default=_utcnow)

    def recompute_trust_score(self):
        score = 50
        score += min(self.txn_count * 3, 25)
        score -= min(self.flagged_txn_count * 15, 45)
        self.trust_score = max(5, min(95, score))

    def to_dict(self):
        return {
            'id': self.id,
            'user_upi_id': self.user_upi_id,
            'counterpart_upi_id': self.counterpart_upi_id,
            'txn_count': self.txn_count,
            'total_amount': self.total_amount,
            'avg_amount': self.avg_amount,
            'flagged_txn_count': self.flagged_txn_count,
            'trust_score': self.trust_score,
            'last_txn_at': self.last_txn_at.isoformat() if self.last_txn_at else None,
            'created_at': self.created_at.isoformat() if self.created_at else None,
        }


class SpamFlag(db.Model):
    __tablename__ = 'spam_flags'
    __table_args__ = (
        CheckConstraint('flagged_upi_id IS NOT NULL OR flagged_phone IS NOT NULL'),
    )

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    reporter_upi_id = db.Column(db.String, nullable=False)
    flagged_upi_id = db.Column(db.String, nullable=True)
    flagged_phone = db.Column(db.String, nullable=True)
    reason = db.Column(db.String, default='spam')  # 'spam'|'fraud'|'scam'|'harassment'
    note = db.Column(db.String, nullable=True)
    created_at = db.Column(db.DateTime, default=_utcnow)


class TransactionLog(db.Model):
    __tablename__ = 'transaction_log'

    id = db.Column(db.Integer, primary_key=True, autoincrement=True)
    user_upi_id = db.Column(db.String, nullable=False)
    recipient_upi_id = db.Column(db.String, nullable=False)
    amount = db.Column(db.Float, nullable=False)
    risk_score = db.Column(db.Integer, default=0)
    intervention_level = db.Column(db.String, default='none')
    created_at = db.Column(db.DateTime, default=_utcnow)
