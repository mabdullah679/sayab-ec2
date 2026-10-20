"""Welcome app: a tiny Flask service that greets a visitor by name.

Configuration is read from the environment (see ``create_app``). The module
exposes ``app`` for gunicorn (``gunicorn app:app``) and ``create_app`` for tests.
"""

import json
import logging
import os
import re
import sys
import time

from flask import Flask, jsonify, render_template, request, send_from_directory

DEFAULT_FRONTEND = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "frontend")
MAX_NAME_LEN = 60
# Printable text only: rejects NUL, newlines and other control characters.
_CONTROL = re.compile(r"[\x00-\x1f\x7f]")

access_log = logging.getLogger("sayab.access")


def _configure_logging():
    if access_log.handlers or logging.getLogger().handlers:
        access_log.setLevel(logging.INFO)
        return
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(logging.Formatter("%(message)s"))
    access_log.addHandler(handler)
    access_log.setLevel(logging.INFO)
    access_log.propagate = False


def format_name(raw):
    """Return the title-cased display name, or raise ValueError if invalid."""
    if _CONTROL.search(raw):
        raise ValueError("name contains control characters")
    name = " ".join(word.capitalize() for word in raw.split())
    if len(name) > MAX_NAME_LEN:
        raise ValueError("name too long")
    return name or "Guest"


def create_app():
    _configure_logging()
    app = Flask(
        __name__,
        static_folder=None,
        template_folder=os.path.join(os.path.dirname(os.path.abspath(__file__)), "templates"),
    )
    app.config["FRONTEND_DIR"] = os.path.abspath(os.environ.get("FRONTEND_DIR", DEFAULT_FRONTEND))
    # A name is at most 60 chars; 4 KiB is generous for the whole form body.
    app.config["MAX_CONTENT_LENGTH"] = int(os.environ.get("MAX_BODY_BYTES", "4096"))

    @app.before_request
    def _start_timer():
        request.environ["sayab.t0"] = time.perf_counter()

    @app.after_request
    def _harden_and_log(resp):
        resp.headers["X-Content-Type-Options"] = "nosniff"
        resp.headers["X-Frame-Options"] = "DENY"
        resp.headers["Referrer-Policy"] = "no-referrer"
        resp.headers["Content-Security-Policy"] = (
            "default-src 'self'; style-src 'self'; frame-ancestors 'none'; base-uri 'none'"
        )
        t0 = request.environ.get("sayab.t0")
        # Never log form values (the visitor's name); only request metadata.
        access_log.info(
            json.dumps(
                {
                    "method": request.method,
                    "path": request.path,
                    "status": resp.status_code,
                    "ms": round((time.perf_counter() - t0) * 1000, 2) if t0 else None,
                }
            )
        )
        return resp

    @app.get("/")
    def home():
        return send_from_directory(app.config["FRONTEND_DIR"], "index.html")

    @app.get("/static/<path:filename>")
    def static_files(filename):
        return send_from_directory(app.config["FRONTEND_DIR"], filename)

    @app.post("/submit")
    def submit():
        try:
            name = format_name(request.form.get("user_name", ""))
        except ValueError as exc:
            return jsonify(error=str(exc)), 400
        return render_template("greeting.html", name=name)

    @app.get("/healthz")
    def healthz():
        """Liveness: the process is up and serving."""
        return jsonify(status="ok")

    @app.get("/readyz")
    def readyz():
        """Readiness: the frontend assets this service serves are present."""
        index = os.path.join(app.config["FRONTEND_DIR"], "index.html")
        if not os.path.isfile(index):
            return jsonify(status="not ready", reason="frontend missing"), 503
        return jsonify(status="ready")

    @app.errorhandler(404)
    def not_found(_e):
        return jsonify(error="not found"), 404

    @app.errorhandler(405)
    def bad_method(_e):
        return jsonify(error="method not allowed"), 405

    @app.errorhandler(413)
    def too_large(_e):
        return jsonify(error="request too large"), 413

    @app.errorhandler(500)
    def server_error(_e):
        return jsonify(error="internal error"), 500

    return app


app = create_app()

if __name__ == "__main__":
    app.run(host=os.environ.get("HOST", "127.0.0.1"), port=int(os.environ.get("PORT", "5000")))
