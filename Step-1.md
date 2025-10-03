# SQS

## Create SQS Queue
`aws --endpoint-url=http://localhost:4566 --region us-east-1 sqs create-queue --queue-name inventory-level-changed.fifo --attributes FifoQueue=true,ContentBasedDeduplication=true`

> Obtain the Queue URL from the output


## Get the Queue ARN
`aws --endpoint-url=http://localhost:4566 --region us-east-1 sqs get-queue-attributes --queue-url <QUEUE_URL> --attribute-names QueueArn --query 'Attributes.QueueArn' --output text`


# EventBridge
## Create EventBridge Bus
`aws --endpoint-url=http://localhost:4566 --region us-east-1 events create-event-bus --name gemini`

## Create or Update EventBridge Rules (event-bridge-setup.json)
- Update the `event-bridge-setup.json` file with the correct SQS ARN

## Update the script with correct AccountId and Region
- Update the `script-01-setup-eventbridge.ps1` file with the correct `AccountId` and `Region`

## Run the script to create EventBridge Rules
`.\script-01-setup-eventbridge.ps1 -ConfigFile "inventory-level-changed" -Region "us-east-1" -AccountId "000000000000" -UseLocalStack $true`

`.\script-01-setup-eventbridge.ps1 -ConfigFile "order-submitted" -Region "us-east-1" -AccountId "000000000000" -UseLocalStack $true`

