"""Regression guards for the 2026-11-19 redesign (real layout is proven by the Playwright
showcase suite in mab-site-monitor/e2e; these guard the exact causes found there)."""

import re

import pytest

FORBIDDEN_COLOURS = ["#ffa500", "#008000", "#ffc0cb", "#006400"]  # old orange/green/pink


@pytest.fixture()
def css(client):
    return client.get("/static/styles.css").get_data(as_text=True)


def test_css_has_no_garish_orange_green_pink(css):
    low = css.lower()
    for colour in FORBIDDEN_COLOURS:
        assert colour not in low


def test_css_does_not_reintroduce_sideways_scroll_causes(css):
    # Cause of the old overflow: an absolutely positioned 100%-wide footer plus padding,
    # and a fixed 100vh body with body padding.
    assert not re.search(r"position\s*:\s*absolute", css)
    assert not re.search(r"(?<!min-)height\s*:\s*100vh", css)
    assert re.search(r"box-sizing\s*:\s*border-box", css)


def test_home_has_one_line_what_this_is(client):
    body = client.get("/").get_data(as_text=True)
    assert 'id="what-this-is"' in body
    assert "greets you by name" in body


def test_greeting_page_shows_name_in_heading(client):
    body = client.post("/submit", data={"user_name": "jane doe"}).get_data(as_text=True)
    assert '<h1 id="greeting">Welcome, Jane Doe!</h1>' in body
