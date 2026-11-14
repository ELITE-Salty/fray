from django.urls import path
from tracker import views, auth_views, security_views, product_views

urlpatterns = [
    path('api/auth/csrf', views.csrf), path('api/auth/login', views.sign_in),
    path('api/auth/logout', views.sign_out), path('api/auth/me', views.me),
    path('api/auth/login/start', auth_views.begin_login),
    path('api/auth/login/verify', auth_views.verify_login),
    path('api/auth/challenge', auth_views.status),
    path('api/auth/cancel', auth_views.cancel),
    path('api/auth/signup', auth_views.begin_signup),
    path('api/auth/signup/email', auth_views.verify_email),
    path('api/auth/signup/resend', auth_views.resend_email),
    path('api/auth/signup/finish', auth_views.finish_signup),
    path('api/auth/password/request', security_views.reset_request),
    path('api/auth/password/reset', security_views.reset_finish),
    path('api/account/authenticator/finish', security_views.rotate_finish),
    path('api/account/<str:action>', security_views.account_action),
    path('api/preferences', product_views.preferences),
    path('api/templates', product_views.templates),
    path('api/templates/<uuid:template_id>', product_views.templates),
    path('api/projects/<uuid:item_id>', product_views.project),
    path('api/invitations', product_views.invitations),
    path('api/items', views.items), path('api/items/<uuid:item_id>', views.items),
    path('api/entries', views.entries), path('api/entries/<uuid:entry_id>', views.entries),
    path('api/reports/monthly', views.report), path('api/health', views.health),
    path('metrics', views.metrics),
]
