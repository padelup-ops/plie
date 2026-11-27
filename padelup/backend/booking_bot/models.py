"""Bot de réservation : comptes connectés, règles de réservation automatique et journal."""
from django.contrib.auth.models import User
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models
from django.db.models import Q
from django.utils import timezone

from . import crypto

PROVIDER_CHOICES = [
    ('padelup', 'Clubs partenaires PadelUp'),
    ('playtomic', 'Playtomic'),
    ('anybuddy', 'Anybuddy'),
]


class ProviderAccount(models.Model):
    """Compte d'un joueur sur une plateforme de réservation (jamais le mot de passe, seulement les jetons chiffrés)."""

    STATUS_CHOICES = [
        ('active', 'Connecté'),
        ('needs_reauth', 'Reconnexion requise'),
        ('error', 'Erreur'),
    ]

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='provider_accounts')
    provider = models.CharField(max_length=20, choices=PROVIDER_CHOICES)
    external_user_id = models.CharField(max_length=100, blank=True)
    login_email = models.CharField(max_length=254, blank=True)
    access_token_encrypted = models.TextField(blank=True)
    refresh_token_encrypted = models.TextField(blank=True)
    token_expires_at = models.DateTimeField(null=True, blank=True)
    refresh_expires_at = models.DateTimeField(null=True, blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='active')
    last_error = models.TextField(blank=True)
    reauth_notified = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    last_used_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        unique_together = ('user', 'provider')
        ordering = ['provider']

    def __str__(self):
        return f'{self.user.username} @ {self.provider} ({self.status})'

    @property
    def access_token(self):
        return crypto.decrypt(self.access_token_encrypted)

    @access_token.setter
    def access_token(self, value):
        self.access_token_encrypted = crypto.encrypt(value)

    @property
    def refresh_token(self):
        return crypto.decrypt(self.refresh_token_encrypted)

    @refresh_token.setter
    def refresh_token(self, value):
        self.refresh_token_encrypted = crypto.encrypt(value)

    @property
    def masked_email(self):
        email = self.login_email or ''
        if '@' not in email:
            return email
        name, domain = email.split('@', 1)
        return f'{name[:2]}{"•" * max(1, len(name) - 2)}@{domain}'

    def apply_tokens(self, data):
        """Enregistre les jetons renvoyés par la plateforme (connexion ou renouvellement)."""
        self.access_token = data['access_token']
        if data.get('refresh_token'):
            self.refresh_token = data['refresh_token']
        self.token_expires_at = data.get('token_expires_at')
        if data.get('refresh_expires_at'):
            self.refresh_expires_at = data['refresh_expires_at']
        if data.get('external_user_id'):
            self.external_user_id = data['external_user_id']
        self.status, self.last_error, self.reauth_notified = 'active', '', False
        self.save()

    def mark_needs_reauth(self, message):
        self.status = 'needs_reauth'
        self.last_error = message[:1000]
        self.save(update_fields=['status', 'last_error', 'updated_at'])


class AutoBookingRule(models.Model):
    """Ce que le joueur veut : « le mardi entre 19h et 21h, 90 min, au club X »."""

    MODE_CHOICES = [
        ('book', 'Réserver automatiquement'),
        ('notify', 'Me prévenir seulement'),
    ]
    COURT_CHOICES = [
        ('any', 'Peu importe'),
        ('indoor', 'Intérieur'),
        ('outdoor', 'Extérieur'),
    ]

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='auto_booking_rules')
    provider = models.CharField(max_length=20, choices=PROVIDER_CHOICES)
    account = models.ForeignKey(ProviderAccount, on_delete=models.SET_NULL, null=True, blank=True, related_name='rules')
    name = models.CharField(max_length=120, blank=True)

    club_external_id = models.CharField(max_length=100)
    club_name = models.CharField(max_length=200)
    club_city = models.CharField(max_length=100, blank=True)
    club_timezone = models.CharField(max_length=64, blank=True)
    club_latitude = models.FloatField(null=True, blank=True)
    club_longitude = models.FloatField(null=True, blank=True)

    weekdays = models.JSONField(default=list, blank=True)  # 0 = lundi ... 6 = dimanche
    specific_date = models.DateField(null=True, blank=True)  # réservation ponctuelle
    time_from = models.TimeField()  # heure de début au plus tôt
    time_to = models.TimeField()  # heure de début au plus tard
    durations = models.JSONField(default=list)  # minutes, par ordre de préférence : [90, 60]
    court_preference = models.CharField(max_length=10, choices=COURT_CHOICES, default='any')
    max_price = models.DecimalField(max_digits=8, decimal_places=2, null=True, blank=True)
    days_ahead = models.PositiveIntegerField(default=7, validators=[MinValueValidator(0), MaxValueValidator(30)])
    min_notice_minutes = models.PositiveIntegerField(default=120)

    mode = models.CharField(max_length=10, choices=MODE_CHOICES, default='book')
    is_active = models.BooleanField(default=True)
    max_bookings = models.PositiveIntegerField(default=1)  # 0 = sans limite (récurrent)
    bookings_made = models.PositiveIntegerField(default=0)

    last_checked_at = models.DateTimeField(null=True, blank=True)
    last_status = models.CharField(max_length=20, blank=True)
    last_message = models.TextField(blank=True)
    locked_until = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ['-is_active', '-created_at']

    def __str__(self):
        return self.name or f'{self.club_name} ({self.provider})'

    @property
    def is_exhausted(self):
        return self.max_bookings > 0 and self.bookings_made >= self.max_bookings

    def try_lock(self, seconds=300):
        """Verrou optimiste (fonctionne aussi sous SQLite) pour qu'un créneau ne soit jamais traité deux fois en parallèle."""
        now = timezone.now()
        got = AutoBookingRule.objects.filter(pk=self.pk).filter(
            Q(locked_until__isnull=True) | Q(locked_until__lt=now)
        ).update(locked_until=now + timezone.timedelta(seconds=seconds))
        return got == 1

    def unlock(self):
        AutoBookingRule.objects.filter(pk=self.pk).update(locked_until=None)


class BotAttempt(models.Model):
    """Journal du bot : chaque créneau trouvé, réservé, raté ou signalé."""

    STATUS_CHOICES = [
        ('booked', 'Réservé'),
        ('notified', 'Créneau signalé'),
        ('needs_action', 'Action requise'),
        ('failed', 'Échec'),
        ('auth_error', 'Reconnexion requise'),
    ]

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='bot_attempts')
    rule = models.ForeignKey(AutoBookingRule, on_delete=models.CASCADE, related_name='attempts', null=True, blank=True)
    provider = models.CharField(max_length=20, choices=PROVIDER_CHOICES)
    club_external_id = models.CharField(max_length=100, blank=True)
    club_name = models.CharField(max_length=200, blank=True)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES)
    slot_key = models.CharField(max_length=200, blank=True)
    slot_start = models.DateTimeField(null=True, blank=True)
    slot_date = models.DateField(null=True, blank=True)
    duration = models.PositiveIntegerField(null=True, blank=True)
    court_name = models.CharField(max_length=120, blank=True)
    price = models.CharField(max_length=40, blank=True)
    external_booking_id = models.CharField(max_length=120, blank=True)
    action_url = models.URLField(max_length=500, blank=True)
    message = models.TextField(blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['-created_at']
        indexes = [models.Index(fields=['rule', 'status', 'slot_date'])]

    def __str__(self):
        return f'{self.club_name or self.rule} — {self.status} — {self.slot_start}'
