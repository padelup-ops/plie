from django.contrib import admin

from .models import AutoBookingRule, BotAttempt, ProviderAccount


@admin.register(ProviderAccount)
class ProviderAccountAdmin(admin.ModelAdmin):
    list_display = ('user', 'provider', 'status', 'last_used_at', 'created_at')
    list_filter = ('provider', 'status')
    search_fields = ('user__username', 'user__email')
    exclude = ('access_token_encrypted', 'refresh_token_encrypted')  # jamais affichés


@admin.register(AutoBookingRule)
class AutoBookingRuleAdmin(admin.ModelAdmin):
    list_display = ('__str__', 'user', 'provider', 'mode', 'is_active', 'bookings_made', 'last_status', 'last_checked_at')
    list_filter = ('provider', 'mode', 'is_active', 'last_status')
    search_fields = ('club_name', 'user__username')


@admin.register(BotAttempt)
class BotAttemptAdmin(admin.ModelAdmin):
    list_display = ('created_at', 'user', 'provider', 'club_name', 'status', 'slot_start', 'court_name', 'price')
    list_filter = ('provider', 'status')
    search_fields = ('club_name', 'user__username')
