#!/bin/bash
set -e

echo "=== Creating DynamoDB Table ==="

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

echo "=== Packaging Lambda Functions ==="

# Create create_url lambda package
cd lambdas/create_url
rm -f lambda.zip
zip lambda.zip handler.py
cd ../..

awslocal lambda create-function \
    --function-name create-url \
    --runtime python3.11 \
    --timeout 30 \
    --zip-file fileb://lambdas/create_url/lambda.zip \
    --handler handler.handler \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --environment Variables="{TABLE_NAME=urls,AWS_ENDPOINT_URL=http://host.docker.internal:4566}" # Resolves to host machine from within Docker container

# Wait for the function to be active
awslocal lambda wait function-active-v2 --function-name create-url

# Create redirect_url lambda package
cd lambdas/redirect_url
rm -f lambda.zip
zip lambda.zip handler.py
cd ../..

awslocal lambda create-function \
    --function-name redirect-url \
    --runtime python3.11 \
    --timeout 30 \
    --zip-file fileb://lambdas/redirect_url/lambda.zip \
    --handler handler.handler \
    --role arn:aws:iam::000000000000:role/lambda-role \
    --environment Variables="{TABLE_NAME=urls,AWS_ENDPOINT_URL=http://host.docker.internal:4566}"

awslocal lambda wait function-active-v2 --function-name redirect-url

echo "=== Lambda Functions Created ==="
awslocal lambda list-functions --query 'Functions[].FunctionName'