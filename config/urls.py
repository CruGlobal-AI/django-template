from django.contrib import admin
from django.urls import path
from django.views.generic import TemplateView

# The /health check is answered by config.health.HealthCheckMiddleware.

urlpatterns = [
    path("", TemplateView.as_view(template_name="home.html"), name="home"),
    path("admin/", admin.site.urls),
]
