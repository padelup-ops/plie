from .base import (BookingResult, ProviderAuthError, ProviderClub, ProviderError, Slot,  # noqa: F401
                   SlotUnavailable)
from .anybuddy import AnybuddyProvider
from .padelup import PadelUpProvider
from .playtomic import PlaytomicProvider

PROVIDERS = {p.code: p for p in (PlaytomicProvider, AnybuddyProvider, PadelUpProvider)}


def get_provider(code, user=None, account=None):
    cls = PROVIDERS.get(code)
    if not cls:
        raise ProviderError(f'Plateforme inconnue : {code}')
    return cls(user=user, account=account)
