import json
import os
import hashlib
import boto3
import time
import re

def get_dynamodb_resource():
    """Create a DynamoDB resource configured for LocalStack."""
    endpoint_url = os.environ.get('AWS_ENDPOINT_URL', 'http://localhost:4566')
    return boto3.resource(
        'dynamodb',
        endpoint_url=endpoint_url,
        region_name=os.environ.get('AWS_REGION', 'us-east-1'),
        aws_access_key_id='test',
        aws_secret_access_key='test'
    )
    
def generate_short_code(url: str, length: int = 6) -> str:
    """Generate a short code URL + timestamp hash."""
    hash_input = f"{url}{time.time()}"
    hash_digest = hashlib.sha256(hash_input.encode()).hexdigest()
    return hash_digest[:length]

def validate_custom_code(code: str) -> tuple[bool, str]:
    """Validate custom short code format."""
    if not code:
        return True, "" # Empty is fine, we'll generate one
    
    if not re.match(r'^[a-zA-Z0-9_-]{3,20}$', code):
        return False, "Custom code must be 3-20 characters long and can only contain letters, numbers, hyphens, and underscores."
    
    return True, ""

def code_exists(table, code: str) -> bool:
    """Check if a short code already exists in the DynamoDB table."""
    response = table.get_item(Key={'short_code': code})
    return 'Item' in response

def handler(event, context):
    """Lambda function handler to create a shortened URL."""
    try:
        # parse the incoming request body
        body = json.loads(event.get('body', '{}'))
        original_url = body.get('url')
        custom_code = body.get('custom_code')
        
        if not original_url:
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'message': 'URL is required'})
            }
        
        if not original_url.startswith(('http://', 'https://')):
            return {
                'statusCode': 400,
                'headers': {'Content-Type': 'application/json'},
                'body': json.dumps({'message': 'Invalid URL format'})
            }

        dynamodb = get_dynamodb_resource()
        table = dynamodb.Table(os.environ.get('TABLE_NAME', 'urls'))

        if custom_code:
            is_valid, error_msg = validate_custom_code(custom_code)
            if not is_valid:
                return {
                    'statusCode': 400,
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({'message': error_msg})
                }

            if code_exists(table, custom_code):
                return {
                    'statusCode': 409, # Conflict
                    'headers': {'Content-Type': 'application/json'},
                    'body': json.dumps({'message': 'Custom code already exists'})
                }

            short_code = custom_code  # Use the custom code

        else:
            short_code = generate_short_code(original_url)
        
        item = {
            'short_code': short_code,
            'original_url': original_url,
            'created_at': int(time.time()),
            'click_count': 0
        }
        
        table.put_item(Item=item)
        
        base_url = os.environ.get('BASE_URL', 'http://localhost:4566')
        short_url = f"{base_url}/{short_code}"
        
        return {
            'statusCode': 201,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({
                'short_code': short_code,
                'short_url': short_url,
                'original_url': original_url
            })
        }
        
    except Exception as e:
        return {
            'statusCode': 500,
            'headers': {'Content-Type': 'application/json'},
            'body': json.dumps({'message': 'Internal server error', 'error': str(e)})
        }