import json
import os
import time
import boto3
from decimal import Decimal
from boto3.dynamodb.conditions import Key

class DecimalEncoder(json.JSONEncoder):
    """Custom JSON encoder for DynamoDB Decimal types that `json.dumps` doesn't support natively."""
    def default(self, obj):
        if isinstance(obj, Decimal):
            # Convert to int of whole number, else float
            if obj % 1 == 0:
                return int(obj)
            return float(obj)
        return super().default(obj)

def get_dynamodb_resource():
    endpoint_url = os.environ.get('AWS_ENDPOINT_URL', 'http://localhost:4566')
    return boto3.resource(
        'dynamodb',
        endpoint_url=endpoint_url,
        region_name='us-east-1',
        aws_access_key_id='test',
        aws_secret_access_key='test'
    )
    
def handler(event, context):
    try:
        short_code = event.get('pathParameters', {}).get('short_code')
        query_params = event.get('queryStringParameters', {}) or {}
        
        start_time = int(query_params.get('start_time', 0))
        end_time = int(query_params.get('end_time', int(time.time() * 1000)))
        
        dynamodb = get_dynamodb_resource()
        clicks_table = dynamodb.Table('url_clicks')
        
        response = clicks_table.query(
            KeyConditionExpression=Key('short_code').eq(short_code) &
                                   Key('timestamp').between(start_time, end_time),
            ScanIndexForward=False, # Descending order
            Limit=1000
        )
        
        clicks = response.get('Items', [])
        
        stats = {
            'total_clicks': len(clicks),
            'unique_ips': len(set(click['ip_address'] for click in clicks)),
            'top_referrers': {},
            'clicks': clicks
        }
        
        for click in clicks:
            referrer = click.get('referrer', 'direct')
            stats['top_referrers'][referrer] = stats['top_referrers'].get(referrer, 0) + 1
        
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps(stats, cls=DecimalEncoder)
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'error': str(e)})
        }