import pytest
import requests
import json
import os

BASE_URL = os.environ.get('API_BASE_URL', 'http://localhost:4566')

@pytest.fixture
def api_endpoint():
    """Get the API endpoint from .api_config."""
    with open('.api_config', 'r') as f:
        for line in f:
            if line.startswith('API_ID='):
                api_id = line.strip().split('=')[1]
                return f"{BASE_URL}/restapis/{api_id}/dev/_user_request_"
    raise RuntimeError("API_ID not found in .api_config")


class TestURLShortenerAPI:

    def test_create_and_redirect(self, api_endpoint):
        # Create shortened URL
        create_response = requests.post(
            f"{api_endpoint}/urls",
            json={'url': 'https://httpbin.org/get'}
        )

        assert create_response.status_code == 201
        data = create_response.json()
        assert 'short_code' in data

        short_code = data['short_code']

        # Test redirect (don't follow redirects)
        redirect_response = requests.get(
            f"{api_endpoint}/r/{short_code}",
            allow_redirects=False
        )

        assert redirect_response.status_code == 302
        assert redirect_response.headers['Location'] == 'https://httpbin.org/get'

    def test_create_missing_url(self, api_endpoint):
        response = requests.post(
            f"{api_endpoint}/urls",
            json={}
        )

        assert response.status_code == 400

    def test_redirect_not_found(self, api_endpoint):
        response = requests.get(
            f"{api_endpoint}/r/nonexistent123",
            allow_redirects=False
        )

        assert response.status_code == 404