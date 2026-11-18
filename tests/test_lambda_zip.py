"""The Lambda zip must carry the handler, templates/ and frontend/."""

import os
import subprocess
import zipfile
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parent.parent


@pytest.fixture(scope="module")
def names(tmp_path_factory):
    full = os.environ.get("LAMBDA_ZIP")  # CI points this at a full (deps included) build
    if full:
        zpath = Path(full)
    else:
        zpath = tmp_path_factory.mktemp("zip") / "lambda.zip"
        env = dict(os.environ, SKIP_DEPS="1", OUT=str(zpath))
        subprocess.run(["bash", str(ROOT / "scripts/build_lambda.sh")], check=True, env=env)
    with zipfile.ZipFile(zpath) as z:
        return set(z.namelist())


def test_zip_has_handler_and_app(names):
    assert {"lambda_handler.py", "app.py"} <= names


def test_zip_has_templates(names):
    assert "templates/greeting.html" in names


def test_zip_has_frontend(names):
    assert {"frontend/index.html", "frontend/styles.css"} <= names


@pytest.mark.skipif(not os.environ.get("LAMBDA_ZIP"), reason="full build only")
def test_full_zip_has_dependencies(names):
    assert any(n.startswith("flask/") for n in names)
    assert any(n.startswith("apig_wsgi/") for n in names)
    assert not any(n.startswith("gunicorn") for n in names)
