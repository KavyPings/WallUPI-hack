"""
Wallupi Backend — Flask Server
Provides AI-powered fraud detection APIs for the Wallupi payment app.
"""

from dotenv import load_dotenv
load_dotenv()  # Load AWS Bedrock credentials and other env vars from backend/.env

from flask import Flask
from flask_cors import CORS

from database import db
from routes.analyze_sms import sms_bp
from routes.risk_score import risk_bp
from routes.explain_risk import explain_bp
from routes.cloud_sms_review import cloud_review_bp
from routes.profiles import profiles_bp
from routes.otp import otp_bp

app = Flask(__name__)
CORS(app)

app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///wallupi.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db.init_app(app)

# Register blueprints
app.register_blueprint(sms_bp)
app.register_blueprint(risk_bp)
app.register_blueprint(explain_bp)
app.register_blueprint(cloud_review_bp)
app.register_blueprint(profiles_bp)
app.register_blueprint(otp_bp)

with app.app_context():
    db.create_all()


@app.route('/')
def health():
    return {
        'status': 'ok',
        'service': 'Wallupi Fraud Detection API',
        'version': '2.0.0',
        'endpoints': [
            '/analyze-sms',
            '/risk-score',
            '/explain-risk',
            '/cloud-review',
            '/profile/transaction',
            '/profile/user/<upi_id>',
            '/profile/relationship',
            '/spam/flag',
            '/spam/check',
            '/status',
        ]
    }


@app.route('/status')
def api_status():
    """Lightweight probe used by the admin login screen to light up AI indicators."""
    from routes.cloud_sms_review import bedrock_ready
    ready = bedrock_ready()
    return {
        'backend': 'ok',
        'cloud_configured': ready,
        'cloud_provider': 'bedrock-gpt-oss-120b',
        # Backward-compat alias for app builds that still read the old key.
        'gemini_configured': ready,
    }


if __name__ == '__main__':
    print("Wallupi Backend running on http://0.0.0.0:5000")
    app.run(host='0.0.0.0', port=5000, debug=True)
