
# Queue Spelunker

This is a simple tool designed to find any deprecated mirrored queues in a cloud foundry foundation. 

## Create the virtual environment

    python3 -m venv venv

## Activate the virtual environment
    
    source venv/bin/activate

## Install the requirements
    
    pip install -r requirements.txt

    source venv/bin/activate

### Run the Tool

```
python queuespelunker.py

Analyzing RabbitMQ instances...
Checking instance: rabbitmq-alpha-dev in test-org-alpha/dev
DEBUG: Getting credentials for service: rabbitmq-alpha-dev in test-org-alpha/dev
Checking instance: rabbitmq-beta-qa in test-org-beta/qa
DEBUG: Getting credentials for service: rabbitmq-beta-qa in test-org-beta/qa
Checking instance: rabbitmq-gamma-dev in test-org-gamma/dev
DEBUG: Getting credentials for service: rabbitmq-gamma-dev in test-org-gamma/dev

Found instances using classic queue mirroring:
[
  {
    "service_instance": "rabbitmq-alpha-dev",
    "organization": "test-org-alpha",
    "space": "dev",
    "mirrored_queues": [
      {
        "name": "mirror.critical.queue",
        "policy": "ha-policy",
        "mirrors": 2,
        "synchronized_mirrors": 2,
        "policy_definition": {
          "ha-mode": "all",
          "ha-sync-mode": "automatic"
        }
      },
      {
        "name": "mirror.important.queue",
        "policy": "ha-policy",
        "mirrors": 2,
        "synchronized_mirrors": 2,
        "policy_definition": {
          "ha-mode": "all",
          "ha-sync-mode": "automatic"
        }
      },
      {
        "name": "mirror.metrics.queue",
        "policy": "ha-policy",
        "mirrors": 2,
        "synchronized_mirrors": 2,
        "policy_definition": {
          "ha-mode": "all",
          "ha-sync-mode": "automatic"
        }
      },
      {
        "name": "mirror.test.queue",
        "policy": "ha-policy",
        "mirrors": 2,
        "synchronized_mirrors": 2,
        "policy_definition": {
          "ha-mode": "all",
          "ha-sync-mode": "automatic"
        }
      }
    ]
  },
  {
    "service_instance": "rabbitmq-beta-qa",
    "organization": "test-org-beta",
    "space": "qa",
    "mirrored_queues": [
      {
        "name": "beta.critical.queue",
        "policy": "ha-policy-beta",
        "mirrors": 2,
        "synchronized_mirrors": 2,
        "policy_definition": {
          "ha-mode": "all",
          "ha-sync-mode": "automatic"
        }
      },
      {
        "name": "beta.important.queue",
        "policy": "ha-policy-beta",
        "mirrors": 2,
        "synchronized_mirrors": 2,
        "policy_definition": {
          "ha-mode": "all",
          "ha-sync-mode": "automatic"
        }
      },
      {
        "name": "beta.metrics.queue",
        "policy": "ha-policy-beta",
        "mirrors": 2,
        "synchronized_mirrors": 2,
        "policy_definition": {
          "ha-mode": "all",
          "ha-sync-mode": "automatic"
        }
      },
      {
        "name": "beta.test.queue",
        "policy": "ha-policy-beta",
        "mirrors": 2,
        "synchronized_mirrors": 2,
        "policy_definition": {
          "ha-mode": "all",
          "ha-sync-mode": "automatic"
        }
      }
    ]
  }
]
        
Summary:

Instance: rabbitmq-alpha-dev in test-org-alpha/dev

Mirrored Queues:
  - Queue: mirror.critical.queue
    Policy: ha-policy
    Mirrors: 2 (2 synchronized)
  - Queue: mirror.important.queue
    Policy: ha-policy
    Mirrors: 2 (2 synchronized)
  - Queue: mirror.metrics.queue
    Policy: ha-policy
    Mirrors: 2 (2 synchronized)
  - Queue: mirror.test.queue
    Policy: ha-policy
    Mirrors: 2 (2 synchronized)

Instance: rabbitmq-beta-qa in test-org-beta/qa

Mirrored Queues:
  - Queue: beta.critical.queue
    Policy: ha-policy-beta
    Mirrors: 2 (2 synchronized)
  - Queue: beta.important.queue
    Policy: ha-policy-beta
    Mirrors: 2 (2 synchronized)
  - Queue: beta.metrics.queue
    Policy: ha-policy-beta
    Mirrors: 2 (2 synchronized)
  - Queue: beta.test.queue
    Policy: ha-policy-beta
    Mirrors: 2 (2 synchronized)
```

The output above indicates it found four deprecated mirrored queues. 

    

## When you're done
    
    deactivate
