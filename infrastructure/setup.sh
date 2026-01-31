#!/bin/bash
set -e

echo ""
echo "=== Creating DynamoDB Table ==="

# Check if table already exists
if awslocal dynamodb describe-table --table-name urls &> /dev/null; then
    echo "DynamoDB table 'urls' already exists. Skipping creation."
else 
    awslocal dynamodb create-table \
        --table-name urls \
        --attribute-definitions \
            AttributeName=short_code,AttributeType=S \
        --key-schema \
            AttributeName=short_code,KeyType=HASH \
        --billing-mode PAY_PER_REQUEST \
        --tags Key=Project,Value=url-shortener

    awslocal dynamodb update-table \
        --table-name urls \
        --attribute-definitions \
            AttributeName=original_url,AttributeType=S \
        --global-secondary-index-updates \
            "[{\"Create\":{\"IndexName\":\"original-url-index\",\"KeySchema\":[{\"AttributeName\":\"original_url\",\"KeyType\":\"HASH\"}],\"Projection\":{\"ProjectionType\":\"ALL\"}}}]"

    echo "=== DynamoDB Table Created ==="
    awslocal dynamodb describe-table --table-name urls --query 'Table.TableStatus'
fi

echo ""
echo "=== Packaging Lambda Functions ==="

# Create create_url lambda package
cd lambdas/create_url
rm -f lambda.zip
zip lambda.zip handler.py
cd ../..

if awslocal lambda get-function --function-name create-url &> /dev/null; then
    echo "Updating existing create-url Lambda function..."
    awslocal lambda update-function-code \
        --function-name create-url \
        --zip-file fileb://lambdas/create_url/lambda.zip
else
    echo "Creating new create-url Lambda function..."
    awslocal lambda create-function \
        --function-name create-url \
        --runtime python3.11 \
        --timeout 30 \
        --zip-file fileb://lambdas/create_url/lambda.zip \
        --handler handler.handler \
        --role arn:aws:iam::000000000000:role/lambda-role \
        --environment Variables="{TABLE_NAME=urls,AWS_ENDPOINT_URL=http://host.docker.internal:4566}" # Resolves to host machine from within Docker container
fi

# Wait for the function to be active
awslocal lambda wait function-active-v2 --function-name create-url

# Create redirect_url lambda package
cd lambdas/redirect_url
rm -f lambda.zip
zip lambda.zip handler.py
cd ../..

if awslocal lambda get-function --function-name redirect-url &> /dev/null; then
    echo "Updating existing redirect-url Lambda function..."
    awslocal lambda update-function-code \
        --function-name redirect-url \
        --zip-file fileb://lambdas/redirect_url/lambda.zip
else
    echo "Creating new redirect-url Lambda function..."
    awslocal lambda create-function \
        --function-name redirect-url \
        --runtime python3.11 \
        --timeout 30 \
        --zip-file fileb://lambdas/redirect_url/lambda.zip \
        --handler handler.handler \
        --role arn:aws:iam::000000000000:role/lambda-role \
        --environment Variables="{TABLE_NAME=urls,AWS_ENDPOINT_URL=http://host.docker.internal:4566}"
fi

awslocal lambda wait function-active-v2 --function-name redirect-url

echo "=== Lambda Functions Created ==="
awslocal lambda list-functions --query 'Functions[].FunctionName'

echo ""
echo "=== Creating API Gateway ==="

EXISTING_API_ID=$(awslocal apigateway get-rest-apis --query "items[?name=='url-shortener-api'].id" --output text)
if [ -n "$EXISTING_API_ID" ] && [ "$EXISTING_API_ID" != "None" ]; then
    echo "API already exists with ID: $EXISTING_API_ID"
    API_ID=$EXISTING_API_ID
else
    API_ID=$(awslocal apigateway create-rest-api \
        --name url-shortener-api \
        --description "URL Shortener API" \
        --query 'id' --output text)
    echo "API ID: $API_ID"

    ROOT_ID=$(awslocal apigateway get-resources \
        --rest-api-id $API_ID \
        --query 'items[0].id' --output text)

    echo "Root Resource ID: $ROOT_ID"

    URLS_RESOURCE_ID=$(awslocal apigateway create-resource \
        --rest-api-id $API_ID \
        --parent-id $ROOT_ID \
        --path-part urls \
        --query 'id' --output text)

    echo "Created /urls resource: $URLS_RESOURCE_ID"

    awslocal apigateway put-method \
        --rest-api-id $API_ID \
        --resource-id $URLS_RESOURCE_ID \
        --http-method POST \
        --authorization-type "NONE"

    awslocal apigateway put-integration \
        --rest-api-id $API_ID \
        --resource-id $URLS_RESOURCE_ID \
        --http-method POST \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:create-url/invocations

    R_RESOURCE_ID=$(awslocal apigateway create-resource \
        --rest-api-id $API_ID \
        --parent-id $ROOT_ID \
        --path-part r \
        --query 'id' --output text)

    SHORT_CODE_RESOURCE_ID=$(awslocal apigateway create-resource \
        --rest-api-id $API_ID \
        --parent-id $R_RESOURCE_ID \
        --path-part '{short_code}' \
        --query 'id' --output text)

    awslocal apigateway put-method \
        --rest-api-id $API_ID \
        --resource-id $SHORT_CODE_RESOURCE_ID \
        --http-method GET \
        --authorization-type "NONE" \
        --request-parameters "method.request.path.short_code=true"

    awslocal apigateway put-integration \
        --rest-api-id $API_ID \
        --resource-id $SHORT_CODE_RESOURCE_ID \
        --http-method GET \
        --type AWS_PROXY \
        --integration-http-method POST \
        --uri arn:aws:apigateway:us-east-1:lambda:path/2015-03-31/functions/arn:aws:lambda:us-east-1:000000000000:function:redirect-url/invocations

    awslocal apigateway create-deployment \
        --rest-api-id $API_ID \
        --stage-name dev
fi

echo "=== API Gateway Created ==="
echo "API Endpoint: http://localhost:4566/restapis/$API_ID/dev/_user_request_/"

# Save for later use
echo "API_ID=$API_ID" > .api_config