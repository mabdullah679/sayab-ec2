import app as app_module
import pytest


@pytest.fixture()
def client():
    flask_app = app_module.create_app()
    flask_app.config["TESTING"] = True
    return flask_app.test_client()
