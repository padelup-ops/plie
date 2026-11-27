from rest_framework import serializers

from .models import AutoBookingRule, BotAttempt, ProviderAccount
from .providers import PROVIDERS

ALLOWED_DURATIONS = (60, 90, 120)


class ProviderAccountSerializer(serializers.ModelSerializer):
    provider_name = serializers.SerializerMethodField()
    login_email = serializers.CharField(source='masked_email', read_only=True)

    class Meta:
        model = ProviderAccount
        fields = ['id', 'provider', 'provider_name', 'login_email', 'status', 'last_error', 'created_at', 'last_used_at']
        read_only_fields = fields

    def get_provider_name(self, obj):
        cls = PROVIDERS.get(obj.provider)
        return cls.name if cls else obj.provider


class ConnectAccountSerializer(serializers.Serializer):
    provider = serializers.ChoiceField(choices=[c for c, p in PROVIDERS.items() if p.needs_account])
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True, trim_whitespace=False, max_length=256)


class BotAttemptSerializer(serializers.ModelSerializer):
    class Meta:
        model = BotAttempt
        fields = ['id', 'rule', 'provider', 'club_external_id', 'club_name', 'status', 'slot_start', 'slot_date',
                  'duration', 'court_name', 'price', 'external_booking_id', 'action_url', 'message', 'created_at']
        read_only_fields = fields


class AutoBookingRuleSerializer(serializers.ModelSerializer):
    account_status = serializers.CharField(source='account.status', read_only=True, default=None)
    recent_attempts = serializers.SerializerMethodField()

    class Meta:
        model = AutoBookingRule
        fields = ['id', 'provider', 'account', 'account_status', 'name', 'club_external_id', 'club_name', 'club_city',
                  'club_timezone', 'club_latitude', 'club_longitude', 'weekdays', 'specific_date', 'time_from',
                  'time_to', 'durations', 'court_preference', 'max_price', 'days_ahead', 'min_notice_minutes', 'mode',
                  'is_active', 'max_bookings', 'bookings_made', 'last_checked_at', 'last_status', 'last_message',
                  'recent_attempts', 'created_at', 'updated_at']
        read_only_fields = ['account', 'account_status', 'bookings_made', 'last_checked_at', 'last_status',
                            'last_message', 'recent_attempts', 'created_at', 'updated_at']

    def get_recent_attempts(self, obj):
        return BotAttemptSerializer(obj.attempts.all()[:5], many=True).data

    def validate_provider(self, value):
        if value not in PROVIDERS:
            raise serializers.ValidationError('Plateforme inconnue.')
        return value

    def validate_weekdays(self, value):
        try:
            days = sorted({int(d) for d in (value or [])})
        except (TypeError, ValueError):
            raise serializers.ValidationError('Jours invalides (0 = lundi … 6 = dimanche).')
        if any(d < 0 or d > 6 for d in days):
            raise serializers.ValidationError('Jours invalides (0 = lundi … 6 = dimanche).')
        return days

    def validate_durations(self, value):
        try:
            durations = [int(d) for d in (value or [])]
        except (TypeError, ValueError):
            raise serializers.ValidationError('Durées invalides.')
        durations = list(dict.fromkeys(durations))
        if not durations or any(d not in ALLOWED_DURATIONS for d in durations):
            raise serializers.ValidationError('Choisis une ou plusieurs durées parmi 60, 90 et 120 minutes.')
        return durations

    def validate(self, attrs):
        get = lambda k: attrs.get(k, getattr(self.instance, k, None))  # noqa: E731
        if get('time_from') and get('time_to') and get('time_from') > get('time_to'):
            raise serializers.ValidationError({'time_to': "L'heure de fin doit être après l'heure de début."})
        if not get('weekdays') and not get('specific_date'):
            raise serializers.ValidationError({'weekdays': 'Choisis au moins un jour ou une date.'})
        if not get('durations'):
            attrs['durations'] = [90]
        return attrs
