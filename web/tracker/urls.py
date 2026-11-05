from django.urls import path
from . import views
urlpatterns = [
    path('', views.dashboard, name='dashboard'),
    path('entries/', views.entries, name='entries'),
    path('entries/new/', views.entry_edit, name='entry_create'),
    path('entries/<uuid:pk>/edit/', views.entry_edit, name='entry_edit'),
    path('timer/start/', views.timer_start, name='timer_start'),
    path('timer/<uuid:pk>/stop/', views.timer_stop, name='timer_stop'),
    path('items/', views.items, name='items'),
    path('items/new/<str:kind>/', views.item_create, name='item_create'),
    path('items/<str:kind>/<uuid:pk>/archive/', views.item_archive, name='item_archive'),
    path('projects/<uuid:pk>/', views.project_detail, name='project_detail'),
    path('reports/', views.reports, name='reports'),
    path('profile/', views.profile, name='profile'),
]
