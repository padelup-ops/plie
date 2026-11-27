from django.urls import path

from . import views

app_name = 'booking_bot'

urlpatterns = [
    path('providers/', views.ProvidersView.as_view(), name='providers'),
    path('accounts/', views.AccountListView.as_view(), name='accounts'),
    path('accounts/<int:account_id>/', views.AccountDetailView.as_view(), name='account_detail'),
    path('clubs/', views.ClubSearchView.as_view(), name='clubs'),
    path('slots/', views.SlotsView.as_view(), name='slots'),
    path('book/', views.BookNowView.as_view(), name='book'),
    path('rules/', views.RuleListView.as_view(), name='rules'),
    path('rules/<int:rule_id>/', views.RuleDetailView.as_view(), name='rule_detail'),
    path('rules/<int:rule_id>/run/', views.RuleRunView.as_view(), name='rule_run'),
    path('attempts/', views.AttemptListView.as_view(), name='attempts'),
    path('tick/', views.TickView.as_view(), name='tick'),
]
