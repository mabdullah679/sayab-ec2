import json
import logging


def test_home_serves_form_and_stylesheet_link(client):
    r = client.get("/")
    assert r.status_code == 200
    body = r.get_data(as_text=True)
    assert 'name="user_name"' in body
    assert "/static/styles.css" in body


def test_stylesheet_is_actually_served(client):
    r = client.get("/static/styles.css")
    assert r.status_code == 200
    assert "text/css" in r.content_type


def test_submit_greets_with_capitalised_name(client):
    r = client.post("/submit", data={"user_name": "ayesha   asim"})
    assert r.status_code == 200
    assert "Ayesha Asim" in r.get_data(as_text=True)


def test_submit_blank_name_falls_back_to_guest(client):
    r = client.post("/submit", data={"user_name": "   "})
    assert r.status_code == 200
    assert "Guest" in r.get_data(as_text=True)


def test_submit_escapes_html_no_reflected_xss(client):
    payload = "<script>alert(1)</script>"
    r = client.post("/submit", data={"user_name": payload})
    body = r.get_data(as_text=True)
    assert "<script>alert" not in body
    assert "&lt;script&gt;" in body


def test_submit_rejects_overlong_name(client):
    r = client.post("/submit", data={"user_name": "a" * 61})
    assert r.status_code == 400


def test_submit_accepts_name_at_limit(client):
    r = client.post("/submit", data={"user_name": "a" * 60})
    assert r.status_code == 200


def test_submit_rejects_control_characters(client):
    r = client.post("/submit", data={"user_name": "bob\x00evil"})
    assert r.status_code == 400


def test_oversized_body_rejected_with_413(client):
    r = client.post("/submit", data={"user_name": "x" * 100000})
    assert r.status_code == 413


def test_submit_get_not_allowed(client):
    assert client.get("/submit").status_code == 405


def test_healthz_is_ok_json(client):
    r = client.get("/healthz")
    assert r.status_code == 200
    assert r.get_json() == {"status": "ok"}


def test_readyz_ok_when_frontend_present(client):
    r = client.get("/readyz")
    assert r.status_code == 200
    assert r.get_json()["status"] == "ready"


def test_readyz_503_when_frontend_missing(client, monkeypatch, tmp_path):
    client.application.config["FRONTEND_DIR"] = str(tmp_path)
    r = client.get("/readyz")
    assert r.status_code == 503


def test_security_headers_present(client):
    h = client.get("/").headers
    assert h["X-Content-Type-Options"] == "nosniff"
    assert h["X-Frame-Options"] == "DENY"
    assert "default-src 'self'" in h["Content-Security-Policy"]
    assert h["Referrer-Policy"] == "no-referrer"


def test_unknown_route_json_404(client):
    r = client.get("/nope")
    assert r.status_code == 404
    assert r.get_json()["error"] == "not found"


def test_request_logs_are_structured_json(client, caplog):
    with caplog.at_level(logging.INFO, logger="sayab.access"):
        client.get("/healthz")
    rec = [r for r in caplog.records if r.name == "sayab.access"][-1]
    data = json.loads(rec.getMessage())
    assert data["path"] == "/healthz" and data["status"] == 200 and "ms" in data


def test_user_name_not_written_to_logs(client, caplog):
    with caplog.at_level(logging.INFO, logger="sayab.access"):
        client.post("/submit", data={"user_name": "SecretPerson"})
    assert all("SecretPerson" not in r.getMessage() for r in caplog.records)
