"""Prometheus metric definitions and export helper."""

from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram, generate_latest

REQUESTS_TOTAL = Counter(
    "gec_requests_total",
    "Total API requests",
    ["endpoint", "outcome"],
)
STREAMS_ACTIVE = Gauge("gec_streams_active", "Active streaming responses")
STREAMS_TOTAL = Counter("gec_streams_total", "Completed streaming responses", ["outcome"])
CACHE_HITS = Counter("gec_cache_hits_total", "Cache hits")
REQUEST_LATENCY = Histogram(
    "gec_request_latency_seconds", "Request latency in seconds", ["endpoint"]
)
STREAM_DURATION = Histogram("gec_stream_duration_seconds", "Stream duration in seconds")


def render_metrics() -> bytes:
    """Render current metric values in Prometheus text format."""
    return generate_latest()


METRICS_CONTENT_TYPE = CONTENT_TYPE_LATEST
