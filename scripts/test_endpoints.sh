#!/bin/bash
set -e

# Load API config
source .api_config

BASE_URL="http://localhost:4566/restapis/$API_ID/dev/_user_request_"

echo "=== Testing URL Shortener API ==="
echo "Base URL: $BASE_URL"
echo ""

# Test 1: Create a shortened URL
echo "1. Creating shortened URL..."
CREATE_RESPONSE=$(curl -s -X POST "$BASE_URL/urls" \
    -H "Content-Type: application/json" \
    -d '{"url": "https://www.example.com/very/long/url/path"}')

echo "Response: $CREATE_RESPONSE"
SHORT_CODE=$(echo $CREATE_RESPONSE | jq -r '.short_code')
echo "Short Code: $SHORT_CODE"
echo ""

# Test 2: Redirect (follow redirect disabled to see 302)
echo "2. Testing redirect (should return 302)..."
curl -s -I "$BASE_URL/r/$SHORT_CODE" | head -5
echo ""

# Test 3: Create another URL
echo "3. Creating another shortened URL..."
curl -s -X POST "$BASE_URL/urls" \
    -H "Content-Type: application/json" \
    -d '{"url": "https://github.com"}'
echo ""
echo ""

# Test 4: Error case - missing URL
echo "4. Testing error case (missing URL)..."
curl -s -X POST "$BASE_URL/urls" \
    -H "Content-Type: application/json" \
    -d '{}'
echo ""
echo ""

# Test 5: Error case - invalid short code
echo "5. Testing 404 (invalid short code)..."
curl -s "$BASE_URL/r/invalid123"
echo ""
echo ""

# Test 6: Scan DynamoDB to see stored URLs
echo "6. Scanning DynamoDB table..."
awslocal dynamodb scan --table-name urls \
    --query 'Items[].{short_code:short_code.S,url:original_url.S,clicks:click_count.N}'

echo ""
echo "=== All tests completed ==="