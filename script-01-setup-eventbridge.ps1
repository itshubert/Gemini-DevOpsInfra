param(
    [string]$ConfigFile = "event-bridge-setup.json",
    [string]$Region = "us-east-1",
    [string]$AccountId = "000000000000",
    [bool]$UseLocalStack = $true
)

# param(
#     [string]$ConfigFile = "event-bridge-setup.json",
#     [string]$Region = "ap-southeast-2",
#     [string]$AccountId = "173445891702",
#     [bool]$UseLocalStack = $true
# )

function CreateSQSQueueIfNotExist-Return-Arn {
    param(
        [string]$QueueName,
        [string]$Region,
        [bool]$UseLocalStack
    )
    
    Write-Host "Creating SQS queue: $QueueName" -ForegroundColor Green

    # Check if queue already exists
    $existingQueueUrl = if ($UseLocalStack) {
        aws --endpoint-url=http://localhost:4566 --region $Region sqs get-queue-url --queue-name $QueueName --query 'QueueUrl' --output text 2>$null
    } else {
        aws --region $Region sqs get-queue-url --queue-name $QueueName --query 'QueueUrl' --output text 2>$null
    }

    if ($existingQueueUrl) {
        Write-Host "SQS queue already exists: $existingQueueUrl" -ForegroundColor Yellow
    }
    # Create the queue if it does not exist
    if ($UseLocalStack) {
        aws --endpoint-url=http://localhost:4566 `
            --region $Region `
            sqs create-queue `
            --queue-name $QueueName `
            --attributes '{"FifoQueue":"true","ContentBasedDeduplication":"true"}' | Out-Null
    } else {
        aws --region $Region `
            sqs create-queue `
            --queue-name $QueueName `
            --attributes '{"FifoQueue":"true","ContentBasedDeduplication":"true"}' | Out-Null
    }

    # Get Queue URL
    $existingQueueUrl = if ($UseLocalStack) {
        aws --endpoint-url=http://localhost:4566 --region $Region sqs get-queue-url --queue-name $QueueName --query 'QueueUrl' --output text
    } else {
        aws --region $Region sqs get-queue-url --queue-name $QueueName --query 'QueueUrl' --output text
    }
    
    # Return ARN
    if ($UseLocalStack) {
        $queueArn = (aws --endpoint-url=http://localhost:4566 --region $Region sqs get-queue-attributes --queue-url $existingQueueUrl --attribute-names QueueArn --query 'Attributes.QueueArn' --output text) | Select-Object -Last 1
    } else {
        $queueArn = (aws --region $Region sqs get-queue-attributes --queue-url $existingQueueUrl --attribute-names QueueArn --query 'Attributes.QueueArn' --output text) | Select-Object -Last 1
    }

    Write-Host "SQS Queue ARN: $queueArn" -ForegroundColor Cyan

    return [string]$queueArn
}

function New-EventBridgeRuleWithTargets {
    param(
        [string]$RuleName,
        [object]$EventPattern,
        [object]$Targets,
        [string]$Region,
        [string]$EventBusName,
        [bool]$UseLocalStack
    )
    
    Write-Host "Creating EventBridge rule: $RuleName" -ForegroundColor Green
    
    $eventPatternJson = $EventPattern | ConvertTo-Json -Compress -Depth 10
    
    if ($UseLocalStack) {
        aws --endpoint-url=http://localhost:4566 `
            --region $Region `
            events put-rule `
            --name $RuleName `
            --event-pattern $eventPatternJson `
            --state ENABLED `
            --event-bus-name $EventBusName `
    } else {
        aws --region $Region `
            events put-rule `
            --name $RuleName `
            --event-pattern $eventPatternJson `
            --state ENABLED `
            --event-bus-name $EventBusName `
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to create rule: $RuleName"
    }
    
    Write-Host "Adding targets to rule: $RuleName" -ForegroundColor Yellow
    
    foreach( $target in $Targets) {
        if ($target.PSObject.Properties.Name -contains "queueName") {
            $queueName = $target.queueName
            $queueArn = CreateSQSQueueIfNotExist-Return-Arn -QueueName $queueName -Region $Region -UseLocalStack $UseLocalStack

            Write-Host "ARN received: $queueArn" -ForegroundColor Cyan

            # Arn property and assign value of $queueArn string type
            $target | Add-Member -MemberType NoteProperty -Name "Arn" -Value $queueArn -Force
            # Remove queueName property
            $target.PSObject.Properties.Remove("queueName")
        }
    }

    # Display to console targets
    Write-Host "Targets to be added:" -ForegroundColor Magenta
    $Targets | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 10 | Write-Host -ForegroundColor Gray }
    
    $targetsJson = $Targets | ConvertTo-Json -Compress -Depth 10

    if ($UseLocalStack) {
        aws --endpoint-url=http://localhost:4566 `
            --region $Region `
            events put-targets `
            --rule $RuleName `
            --targets $targetsJson `
            --event-bus-name $EventBusName `
    } else {
        aws --region $Region `
            events put-targets `
            --rule $RuleName `
            --targets $targetsJson `
            --event-bus-name $EventBusName `
    }
    
    
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to add targets to rule: $RuleName"
    }
}

# Function to set SQS queue policy
function Set-SqsQueuePolicy {
    param(
        [string]$QueueArn,
        [string]$Region,
        [string]$AccountId,
        [bool]$UseLocalStack
    )
    
    # Extract queue name from ARN
    $queueName = $QueueArn.Split(':')[-1]
    $queueUrl = if ($UseLocalStack) {
        "https://sqs.$Region.localhost.localstack.cloud:4566/$AccountId/$queueName"
    } else {
        "https://sqs.$Region.amazonaws.com/$AccountId/$queueName"
    }
    
    Write-Host "Setting SQS policy for queue: $queueName" -ForegroundColor Cyan
    
    $policy = @{
        Version = "2012-10-17"
        Statement = @(
            @{
                Effect = "Allow"
                Principal = @{
                    Service = "events.amazonaws.com"
                }
                Action = "sqs:SendMessage"
                Resource = $QueueArn
            }
        )
    }

    # Create attributes structure with the policy
    $attributes = @{
        Policy = ($policy | ConvertTo-Json -Compress -Depth 10)
    }

    # Create a temporary file for the attributes
    $tempAttributesFile = [System.IO.Path]::GetTempFileName()
    # Write attributes as JSON
    $attributes | ConvertTo-Json -Compress | Out-File -FilePath $tempAttributesFile -Encoding utf8 -NoNewline
    
    # display value of $tempAttributesFile and its contents for debugging
    Write-Host "Temporary Attributes File: $tempAttributesFile" -ForegroundColor Magenta
    Write-Host "Attributes Content:" -ForegroundColor Magenta
    Get-Content $tempAttributesFile | Write-Host -ForegroundColor Gray

    try {
        if ($UseLocalStack) {
            aws --endpoint-url=http://localhost:4566 --region $Region `
                sqs set-queue-attributes `
                --queue-url $queueUrl `
                --attributes file://$tempAttributesFile
        } else {
            aws --region $Region `
                sqs set-queue-attributes `
                --queue-url $queueUrl `
                --attributes file://$tempAttributesFile
        }
        
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to set policy for queue: $queueName"
            Write-Host "Queue URL used: $queueUrl" -ForegroundColor Red
            Write-Host "Attributes JSON:" -ForegroundColor Red
            Get-Content $tempAttributesFile | Write-Host -ForegroundColor Red
        }
    }
    finally {
        # Clean up temporary file
        if (Test-Path $tempAttributesFile) {
            Remove-Item $tempAttributesFile -Force
        }
    }
}

# Main script
try {
    # Validation
    if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
        Write-Error "AWS CLI is not installed or not in PATH"
        exit 1
    }
    
    if (-not (Test-Path $ConfigFile)) {
        Write-Error "Configuration file not found: $ConfigFile"
        exit 1
    }
    
    Write-Host "Starting SQS and EventBridge setup..." -ForegroundColor Cyan
    Write-Host "Region: $Region" -ForegroundColor Cyan
    Write-Host "Config: $ConfigFile" -ForegroundColor Cyan
    Write-Host "UseLocalStack: $UseLocalStack" -ForegroundColor Cyan
    
    # Read configuration
    $config = Get-Content $ConfigFile -Raw | ConvertFrom-Json
    
    Write-Host "Event Bus Name: $($config.eventBusName)" -ForegroundColor Cyan
    Write-Host "Queue Name: $($config.queueName)" -ForegroundColor Cyan
    
    # Track unique SQS ARNs for policy setup
    $sqsArns = @()
    
    # Process each rule
    foreach ($rule in $config.rules) {
        New-EventBridgeRuleWithTargets -RuleName $rule.name -EventPattern $rule.eventPattern -QueueName -Targets $rule.targets -Region $Region -EventBusName $($config.eventBusName) -UseLocalStack $UseLocalStack

        # Collect SQS ARNs from targets
        foreach ($target in $rule.targets) {
            if ($target.Arn -match "arn:aws:sqs:" -and $target.Arn -notin $sqsArns) {
                $sqsArns += $target.Arn
            }
        }
    }

    # Write to console the SQS ARNs found
    Write-Host "`nSQS ARNs found for policy setup:" -ForegroundColor Cyan
    foreach ($arn in $sqsArns) {
        Write-Host $arn -ForegroundColor Yellow
    }
    
    # Set SQS policies
    Write-Host "`nSetting up SQS queue policies..." -ForegroundColor Cyan
    foreach ($sqsArn in $sqsArns) {
        Set-SqsQueuePolicy -QueueArn $sqsArn -Region $Region -AccountId $AccountId -UseLocalStack $UseLocalStack
    }
    
    Write-Host "`n✅ EventBridge setup completed successfully!" -ForegroundColor Green
    
    # Display summary
    Write-Host "`nCreated rules:" -ForegroundColor Cyan

    if ($UseLocalStack) {
        aws --endpoint-url=http://localhost:4566 events list-rules --region $Region --query "Rules[?starts_with(Name, 'Product')].{Name:Name, State:State}" --output table
    } else {
        aws events list-rules --region $Region --query "Rules[?starts_with(Name, 'Product')].{Name:Name, State:State}" --output table
    }
}
catch {
    Write-Error "Setup failed: $_"
    exit 1
}