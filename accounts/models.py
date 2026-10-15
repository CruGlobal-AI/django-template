from django.contrib.auth.models import AbstractUser


class User(AbstractUser):
    """Same as Django's default User for now. Exists so we can add fields later
    (for example when Okta/IAP login is added) with a normal migration."""
