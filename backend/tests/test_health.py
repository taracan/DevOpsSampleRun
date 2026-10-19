"""Health checks: both addresses answer {"status": "ok"}.

/health is what the load balancer calls; /api/v1/health is what the deploy
workflow's smoke test calls through CloudFront.
"""

import pytest


@pytest.mark.parametrize("path", ["/health", "/api/v1/health"])
def test_health(client, path):
    response = client.get(path)

    assert response.status_code == 200
    assert response.json() == {"status": "ok"}
