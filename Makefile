.PHONY: start stop setup test clean

start:
	docker-compose up -d
	@echo "Waiting for LocalStack..."
	@sleep 5
	@curl -s http://localhost:4566/_localstack/health | python3 -m json.tool

stop:
	docker-compose down

setup: start
	@chmod +x infrastructure/setup.sh
	@./infrastructure/setup.sh

deploy-lambdas:
	@echo "Redeploying create-url Lambda..."
	@cd lambdas/create_url && rm -f lambda.zip && zip lambda.zip handler.py
	@awslocal lambda update-function-code \
		--function-name create-url \
		--zip-file fileb://lambdas/create_url/lambda.zip

	@echo "Redeploying redirect-url Lambda..."
	@cd lambdas/redirect_url && rm -f lambda.zip && zip lambda.zip handler.py
	@awslocal lambda update-function-code \
		--function-name redirect-url \
		--zip-file fileb://lambdas/redirect_url/lambda.zip

test:
	@pytest tests/ -v

test-api:
	@chmod +x scripts/test_endpoints.sh
	@./scripts/test_endpoints.sh

logs:
	docker-compose logs -f localstack

clean: stop
	rm -rf volume/
	rm -f lambdas/*/lambda.zip
	rm -f .api_config

scan-table:
	@awslocal dynamodb scan --table-name urls

list-resources:
	@echo "=== Lambda Functions ==="
	@awslocal lambda list-functions --query 'Functions[].FunctionName'
	@echo "\n=== DynamoDB Tables ==="
	@awslocal dynamodb list-tables
	@echo "\n=== API Gateways ==="
	@awslocal apigateway get-rest-apis --query 'items[].{name:name,id:id}'