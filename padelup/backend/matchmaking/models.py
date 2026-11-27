"""Radar des joueurs : présence approximative, disponibilités, propositions de match.

Même contrat que l'app PadelUp actuelle (padelup-mobile-v2) : radar/, availabilities/, proposals/.
Vie privée : la position est arrondie à ~1 km avant d'être enregistrée, n'est jamais renvoyée (seule une distance
arrondie l'est), et un joueur n'apparaît sur le radar que s'il l'a activé lui-même.
"""
from django.conf import settings
from django.core.validators import MaxValueValidator, MinValueValidator
from django.db import models

TIME_SLOTS = [
    ('morning', 'Matin'),
    ('noon', 'Midi'),
    ('afternoon', 'Après-midi'),
    ('evening', 'Soir'),
    ('night', 'Nuit'),
]


class PlayerPresence(models.Model):
    user = models.OneToOneField(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='presence')
    latitude = models.DecimalField(max_digits=6, decimal_places=2)    # ~1 km de précision, volontairement
    longitude = models.DecimalField(max_digits=6, decimal_places=2)
    visible = models.BooleanField(default=True)
    updated_at = models.DateTimeField(auto_now=True)

    def __str__(self):
        return f'{self.user} ({"visible" if self.visible else "masqué"})'


class Availability(models.Model):
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='availabilities')
    day_of_week = models.PositiveSmallIntegerField(null=True, blank=True, validators=[MaxValueValidator(6)])  # 0 = lundi
    specific_date = models.DateField(null=True, blank=True)
    time_slot = models.CharField(max_length=12, choices=TIME_SLOTS)
    radius_km = models.PositiveSmallIntegerField(default=10, validators=[MinValueValidator(2), MaxValueValidator(50)])
    min_skill = models.PositiveSmallIntegerField(default=1, validators=[MinValueValidator(1), MaxValueValidator(10)])
    max_skill = models.PositiveSmallIntegerField(default=10, validators=[MinValueValidator(1), MaxValueValidator(10)])
    location_text = models.CharField(max_length=120, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ['day_of_week', 'specific_date', 'time_slot']
        constraints = [
            models.CheckConstraint(check=models.Q(day_of_week__isnull=False) | models.Q(specific_date__isnull=False),
                                   name='availability_has_day_or_date'),
        ]


class MatchProposal(models.Model):
    STATUS = [
        ('pending', 'En attente'),
        ('accepted', 'Acceptée'),
        ('declined', 'Refusée'),
        ('cancelled', 'Annulée'),
    ]

    sender = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='proposals_sent')
    receiver = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='proposals_received')
    proposed_date = models.DateField()
    proposed_time_slot = models.CharField(max_length=12, choices=TIME_SLOTS)
    message = models.CharField(max_length=500, blank=True)
    location_text = models.CharField(max_length=120, blank=True)
    location_lat = models.DecimalField(max_digits=9, decimal_places=6, null=True, blank=True)
    location_lng = models.DecimalField(max_digits=10, decimal_places=6, null=True, blank=True)
    status = models.CharField(max_length=10, choices=STATUS, default='pending')
    created_at = models.DateTimeField(auto_now_add=True)
    responded_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ['-created_at']
