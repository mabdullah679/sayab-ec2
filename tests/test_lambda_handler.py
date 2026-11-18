"""Invoke the Lambda handler locally with Function URL (payload v2) events."""

import base64
import json

import lambda_handler
import pytest


def event(method="GET", path="/", body=None, headers=None, b64=False):
    h = {"host": "abc.lambda-url.ap-southeast-2.on.aws"}
    h.update(headers or {})
    return {
        "version": "2.0",
        "routeKey": "$default",
        "rawPath": path,
        "rawQueryString": "",
        "headers": h,
        "requestContext": {
            "http": {
                "method": method,
                "path": path,
                "protocol": "HTTP/1.1",
                "sourceIp": "203.0.113.9",
                "userAgent": "pytest",
            },
            "domainName": "abc.lambda-url.ap-southeast-2.on.aws",
        },
        "body": body,
        "isBase64Encoded": b64,
    }


def form(method, path, text, **kw):
    return event(
        method,
        path,
        body=text,
        headers={"content-type": "application/x-www-form-urlencoded"},
        **kw,
    )


def call(ev):
    return lambda_handler.handler(ev, None)


def hdr(resp, name):
    for k, v in resp["headers"].items():
        if k.lower() == name.lower():
            return v
    return None


def body_of(resp):
    raw = resp["body"]
    if resp.get("isBase64Encoded"):
        return base64.b64decode(raw).decode()
    return raw


def test_home_serves_form():
    r = call(event())
    assert r["statusCode"] == 200
    assert 'name="user_name"' in body_of(r)
    assert "text/html" in hdr(r, "content-type")


def test_static_stylesheet_served_as_css():
    r = call(event(path="/static/styles.css"))
    assert r["statusCode"] == 200
    assert "text/css" in hdr(r, "content-type")


def test_healthz():
    r = call(event(path="/healthz"))
    assert r["statusCode"] == 200
    assert json.loads(body_of(r)) == {"status": "ok"}
    assert "application/json" in hdr(r, "content-type")


def test_readyz_ready():
    r = call(event(path="/readyz"))
    assert r["statusCode"] == 200
    assert json.loads(body_of(r))["status"] == "ready"


def test_readyz_503_when_frontend_missing(monkeypatch, tmp_path):
    monkeypatch.setenv("FRONTEND_DIR", str(tmp_path))
    h = lambda_handler.build_handler()
    r = h(event(path="/readyz"), None)
    assert r["statusCode"] == 503
    assert json.loads(body_of(r))["reason"] == "frontend missing"


def test_submit_greets_via_form_body():
    r = call(form("POST", "/submit", "user_name=jane+doe"))
    assert r["statusCode"] == 200
    assert "Jane Doe" in body_of(r)


def test_submit_base64_body():
    raw = base64.b64encode(b"user_name=ann").decode()
    r = call(form("POST", "/submit", raw, b64=True))
    assert r["statusCode"] == 200
    assert "Ann" in body_of(r)


def test_submit_over_body_limit_rejected_413():
    r = call(form("POST", "/submit", "user_name=" + "a" * 5000))
    assert r["statusCode"] == 413
    assert json.loads(body_of(r)) == {"error": "request too large"}


def test_unknown_route_404_json():
    r = call(event(path="/nope"))
    assert r["statusCode"] == 404
    assert json.loads(body_of(r)) == {"error": "not found"}


def test_wrong_method_405():
    r = call(event("GET", "/submit"))
    assert r["statusCode"] == 405


@pytest.mark.parametrize("path", ["/", "/healthz", "/nope"])
def test_security_headers_present(path):
    r = call(event(path=path))
    assert hdr(r, "x-content-type-options") == "nosniff"
    assert hdr(r, "x-frame-options") == "DENY"
    assert "default-src 'self'" in hdr(r, "content-security-policy")


def test_path_traversal_not_served():
    r = call(event(path="/static/../app.py"))
    assert r["statusCode"] in (400, 404)
    assert "create_app" not in body_of(r)
