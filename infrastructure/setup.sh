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