import base64
import hashlib
from cryptography.fernet import Fernet
from django.conf import settings
from allauth.mfa.adapter import DefaultMFAAdapter


class EncryptedMFAAdapter(DefaultMFAAdapter):
    """Encrypt allauth authenticator secrets with a key derived from SECRET_KEY.

    Keep SECRET_KEY stable and backed up separately from the database. Rotating
    it requires a deliberate secret re-encryption migration, never a fresh key.
    """
    def cipher(self):
        return Fernet(base64.urlsafe_b64encode(hashlib.sha256(settings.SECRET_KEY.encode()).digest()))

    def encrypt(self, text):
        return self.cipher().encrypt(text.encode()).decode()

    def decrypt(self, encrypted_text):
        return self.cipher().decrypt(encrypted_text.encode()).decode()
