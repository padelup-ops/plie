from django.urls import path

from .views import AvailabilityDetailView, AvailabilityListView, ProposalDetailView, ProposalListView, RadarView

urlpatterns = [
    path('radar/', RadarView.as_view(), name='radar'),
    path('availabilities/', AvailabilityListView.as_view(), name='availabilities'),
    path('availabilities/<int:avail_id>/', AvailabilityDetailView.as_view(), name='availability_detail'),
    path('proposals/', ProposalListView.as_view(), name='proposals'),
    path('proposals/<int:proposal_id>/', ProposalDetailView.as_view(), name='proposal_detail'),
]
