"""AWS Lambda entry point (Function URL, payload v2) for the same Flask app.

``apig-wsgi`` translates the Function URL event into a WSGI call, so ``app.py``
runs unchanged. Handler string for Lambda: ``lambda_handler.handler``.
"""

import app as app_module
from apig_wsgi import make_lambda_handler


def build_handler():
    # Re-reads the environment (MAX_BODY_BYTES, FRONTEND_DIR) on each build.
    return make_lambda_handler(app_module.create_app(), binary_support=False)


handler = build_handler()
