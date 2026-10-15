from django.http import HttpResponse


class HealthCheckMiddleware:
    """Answer the Cloud Run health check before any other middleware runs.

    Cloud Run probes hit the container by IP, so the Host header is not in
    ALLOWED_HOSTS. Django would reject that with a 400 and Cloud Run would
    restart the app. Answering here skips host validation. Does not touch
    the database.
    """

    path = "/health"

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        if request.path == self.path:
            return HttpResponse("ok")
        return self.get_response(request)
