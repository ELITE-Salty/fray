import time
from prometheus_client import Counter, Histogram

REQUESTS = Counter('fray_http_requests_total', 'API requests', ['route', 'method', 'status'])
LATENCY = Histogram('fray_http_request_seconds', 'API request latency', ['route'])


class MetricsMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        start = time.monotonic()
        response = self.get_response(request)
        route = getattr(getattr(request, 'resolver_match', None), 'route', 'unmatched')
        if route != 'metrics':
            REQUESTS.labels(route, request.method, str(response.status_code)).inc()
            LATENCY.labels(route).observe(time.monotonic() - start)
        return response
