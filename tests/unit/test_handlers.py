import pytest
import json
from unittest.mock import MagicMock, patch

# Import handlers
import sys
sys.path.insert(0, 'lambdas/create_url')
sys.path.insert(0, 'lambdas/redirect_url')

class TestCreateUrlHandler:

    @patch('handler.get_dynamodb_resource')
    def test_create_url_success(self, mock_dynamodb):
        from lambdas.create_url.handler import handler

        # Mock DynamoDB
        mock_table = MagicMock()
        mock_dynamodb.return_value.Table.return_value = mock_table

        event = {
            'body': json.dumps({'url': 'https://example.com'})
        }

        response = handler(event, None)

        assert response['statusCode'] == 201
        body = json.loads(response['body'])
        assert 'short_code' in body
        assert 'short_url' in body
        assert body['original_url'] == 'https://example.com'

    def test_create_url_missing_url(self):
        from lambdas.create_url.handler import handler

        event = {'body': '{}'}
        response = handler(event, None)

        assert response['statusCode'] == 400
        body = json.loads(response['body'])
        assert 'error' in body

    def test_create_url_invalid_format(self):
        from lambdas.create_url.handler import handler

        event = {'body': json.dumps({'url': 'not-a-valid-url'})}
        response = handler(event, None)

        assert response['statusCode'] == 400


class TestRedirectHandler:

    @patch('handler.get_dynamodb_resource')
    def test_redirect_success(self, mock_dynamodb):
        from lambdas.redirect_url.handler import handler

        # Mock DynamoDB response
        mock_table = MagicMock()
        mock_table.get_item.return_value = {
            'Item': {
                'short_code': 'abc123',
                'original_url': 'https://example.com'
            }
        }
        mock_dynamodb.return_value.Table.return_value = mock_table

        event = {
            'pathParameters': {'short_code': 'abc123'}
        }

        response = handler(event, None)

        assert response['statusCode'] == 302
        assert response['headers']['Location'] == 'https://example.com'

    @patch('handler.get_dynamodb_resource')
    def test_redirect_not_found(self, mock_dynamodb):
        from lambdas.redirect_url.handler import handler

        mock_table = MagicMock()
        mock_table.get_item.return_value = {}
        mock_dynamodb.return_value.Table.return_value = mock_table

        event = {
            'pathParameters': {'short_code': 'invalid'}
        }

        response = handler(event, None)

        assert response['statusCode'] == 404