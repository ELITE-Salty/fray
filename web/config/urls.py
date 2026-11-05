from django.urls import include, path
from django.contrib.staticfiles.views import serve
from django.conf import settings
from tracker import views

urlpatterns = [
    path('health/', views.health, name='health'),
    path('accounts/', include('allauth.urls')),
    path('', include('tracker.urls')),
    # Collected files are served by whitenoise in the container.
]
