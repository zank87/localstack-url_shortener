import json
import os
import boto3
from boto3.dynamodb.conditions import Key

def get_dynamodb_resource():
    endpoint_url = os.environ.get('AWS_ENDPOINT_URL', 'http://localhost:4566')
    return boto3.resource(
        'dynamodb',
        endpoint_url=endpoint_url,
        region_name=os.environ.get('AWS_DEFAULT_REGION', 'us-east-1'),
        aws_access_key_id='test',
        aws_secret_access_key='test'
    )
    
def handler(event, context):
    """Redirect to the original URL and increment click count."""
    try:
        path_parameters = event.get('pathParameters', {})
        short_code = path_parameters.get('short_code')
        
        if not short_code:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'message': 'Short code is required'})
            }
        
        dynamodb = get_dynamodb_resource()
        table = dynamodb.Table(os.environ.get('TABLE_NAME', 'urls'))
        
        response = table.get_item(Key={'short_code': short_code})
        item = response.get('Item')
        
        if not item:
            return {
                'statusCode': 404,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'message': 'URL not found'})
            }
            
        table.update_item(
            Key={'short_code': short_code},
            UpdateExpression='SET click_count = click_count + :inc',
            ExpressionAttributeValues={':inc': 1}
        )
        
        return {
            'statusCode': 302,
            'headers': {
                'Location': item['original_url'],
                'Cache-Control': 'no-cache'
            },
            'body': ''
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'message': str(e)})
        }   