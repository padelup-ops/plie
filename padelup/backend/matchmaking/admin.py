from django.contrib import admin

from .models import Availability, MatchProposal, PlayerPresence

admin.site.register(PlayerPresence)
admin.site.register(Availability)
admin.site.register(MatchProposal)
