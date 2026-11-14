from django.urls import path
from tracker import views

urlpatterns = [
    path('api/auth/csrf', views.csrf), path('api/auth/login', views.sign_in),
    path('api/auth/logout', views.sign_out), path('api/auth/me', views.me),
    path('api/items', views.items), path('api/items/<uuid:item_id>', views.items),
    path('api/entries', views.entries), path('api/entries/<uuid:entry_id>', views.entries),
    path('api/reports/monthly', views.report), path('api/health', views.health),
    path('metrics', views.metrics),
]
