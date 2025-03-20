import subprocess
import json
import sys
import os
from typing import Dict, List, Set, Tuple
import requests


def check_cf_auth() -> bool:
    """Check if user is authenticated with CF CLI"""
    try:
        result = subprocess.run(['cf', 'target'], capture_output=True, text=True)

        if result.returncode != 0:
            print("Error: Not authenticated with CF CLI. Please run 'cf login' first.")
            return False

        if 'org:' not in result.stdout or 'space:' not in result.stdout:
            print("Error: No org/space targeted. Please run 'cf target -o ORG -s SPACE' first.")
            return False

        return True

    except FileNotFoundError:
        print("Error: CF CLI not found. Please install it first.")
        return False


def run_command(cmd: List[str], exit_on_error: bool = True) -> str:
    """Execute a shell command and return output"""
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        return result.stdout
    except subprocess.CalledProcessError as e:
        if not exit_on_error:
            # Print exact error output to debug
            print(f"DEBUG stdout: {e.stdout}")
            print(f"DEBUG stderr: {e.stderr}")
        if exit_on_error:
            print(f"Error executing command {' '.join(cmd)}: {e}")
            sys.exit(1)
        raise  # Re-raise for handle_service_key to catch


def get_service_instances() -> List[Dict]:
    """Get all RabbitMQ service instances across foundation"""
    instances = []

    try:
        # Get all orgs
        orgs_output = run_command(['cf', 'curl', '/v3/organizations'])
        orgs = json.loads(orgs_output)

        if 'resources' not in orgs:
            print("Error: Unexpected API response format for organizations")
            sys.exit(1)

        for org in orgs['resources']:
            org_guid = org['guid']
            org_name = org['name']

            # Get spaces in org
            spaces_output = run_command(['cf', 'curl', f'/v3/spaces?organization_guids={org_guid}'])
            spaces = json.loads(spaces_output)

            if 'resources' not in spaces:
                print(f"Error: Unexpected API response format for spaces in org {org_name}")
                continue

            for space in spaces['resources']:
                space_guid = space['guid']
                space_name = space['name']

                # Get service instances in space
                services_output = run_command(
                    ['cf', 'curl', f'/v3/service_instances?space_guids={space_guid}&type=managed'])
                services = json.loads(services_output)

                if 'resources' not in services:
                    print(f"Error: Unexpected API response format for services in space {space_name}")
                    continue

                for service in services['resources']:
                    # Get service plan details
                    if 'service_plan' in service['relationships']:
                        plan_guid = service['relationships']['service_plan']['data']['guid']
                        plan_output = run_command(['cf', 'curl', f'/v3/service_plans/{plan_guid}'])
                        plan_details = json.loads(plan_output)

                        # Check if service offering is RabbitMQ
                        if 'service_offering' in plan_details['relationships']:
                            offering_guid = plan_details['relationships']['service_offering']['data']['guid']
                            offering_output = run_command(['cf', 'curl', f'/v3/service_offerings/{offering_guid}'])
                            offering_details = json.loads(offering_output)

                            if offering_details.get('name') == 'p.rabbitmq':
                                instances.append({
                                    'guid': service['guid'],
                                    'name': service['name'],
                                    'org_name': org_name,
                                    'space_name': space_name
                                })

    except Exception as e:
        print(f"Error getting service instances: {e}")
        sys.exit(1)

    return instances


def get_instance_credentials(instance_guid: str, org_name: str, space_name: str) -> Dict:
    """Get RabbitMQ credentials from service key"""
    # First target the correct org/space
    run_command(['cf', 'target', '-o', org_name, '-s', space_name])

    # Get the service name using the GUID
    service_info = json.loads(run_command(['cf', 'curl', f'/v3/service_instances/{instance_guid}']))
    service_name = service_info['name']
    print(f"DEBUG: Getting credentials for service: {service_name} in {org_name}/{space_name}")

    try:
        # Get list of service keys
        keys_output = run_command(['cf', 'service-keys', service_name], exit_on_error=False)

        # Split lines and filter empty ones
        lines = [line.strip() for line in keys_output.splitlines() if line.strip()]

        # Remove the "Getting keys..." line and "name" header
        # Real key names will be what's left, if any
        key_names = [line for line in lines
                     if not line.startswith("Getting keys")
                     and not line.lower() == "name"]

        if not key_names:
            print(f"No service keys found for {service_name}")
            return {"error": "no_service_keys"}

        # Use first available key
        service_key_name = key_names[0]
        print(f"Using service key: {service_key_name}")

        # Get the credentials using this key
        key_output = run_command(['cf', 'service-key', service_name, service_key_name], exit_on_error=False)

        # Process the key output
        json_lines = []
        started = False
        for line in key_output.splitlines():
            if '{' in line:
                started = True
            if started:
                json_lines.append(line)

        if not json_lines:
            print("DEBUG: No JSON content found in service key output")
            return {}

        json_content = '\n'.join(json_lines)

        try:
            return json.loads(json_content)
        except json.JSONDecodeError as e:
            print(f"Error parsing credentials JSON: {e}")
            return {}

    except subprocess.CalledProcessError as e:
        if "No service key" in str(e.stdout):
            print(f"No service keys found for {service_name}")
            return {"error": "no_service_keys"}
        print(f"Error getting service key: {e}")
        return {}


def get_service_bindings(instance_guid: str) -> List[Dict]:
    """Get all application bindings for a specific service instance"""
    try:
        # Query the service bindings endpoint
        bindings_output = run_command(
            ['cf', 'curl', f'/v3/service_credential_bindings?service_instance_guids={instance_guid}&type=app'])
        bindings = json.loads(bindings_output)

        if 'resources' not in bindings:
            print(f"Error: Unexpected API response format for service bindings")
            return []

        return bindings['resources']

    except Exception as e:
        print(f"Error getting service bindings: {e}")
        return []


def get_app_env(app_guid: str) -> Dict:
    """Get environment variables for an application"""
    try:
        env_output = run_command(['cf', 'curl', f'/v3/apps/{app_guid}/env'])
        return json.loads(env_output)
    except Exception as e:
        print(f"Error getting app environment: {e}")
        return {}


def extract_rabbitmq_credentials_from_binding(app_guid: str, service_name: str) -> Dict:
    """Extract RabbitMQ credentials from application binding"""
    app_env = get_app_env(app_guid)

    if not app_env or 'system_env_json' not in app_env:
        print(f"No environment variables found for app with GUID {app_guid}")
        return {}

    vcap_services = app_env.get('system_env_json', {}).get('VCAP_SERVICES', {})

    # Find the RabbitMQ service credentials
    # The key might be 'p.rabbitmq' or 'p-rabbitmq' or something else
    for service_type, instances in vcap_services.items():
        if 'rabbitmq' in service_type.lower():
            for instance in instances:
                if instance.get('name') == service_name:
                    print(f"Found RabbitMQ credentials in app binding")
                    return instance.get('credentials', {})

    print(f"No RabbitMQ credentials found in app bindings for service {service_name}")
    return {}


def get_credentials_from_bindings(instance_guid: str, org_name: str, space_name: str) -> Dict:
    """Try to get RabbitMQ credentials from app bindings"""
    # First target the correct org/space
    run_command(['cf', 'target', '-o', org_name, '-s', space_name])

    # Get the service name using the GUID
    service_info = json.loads(run_command(['cf', 'curl', f'/v3/service_instances/{instance_guid}']))
    service_name = service_info['name']

    print(f"Looking for credentials in app bindings for service: {service_name} in {org_name}/{space_name}")

    # Get all bindings for this service instance
    bindings = get_service_bindings(instance_guid)

    if not bindings:
        print(f"No app bindings found for service {service_name}")
        return {}

    print(f"Found {len(bindings)} app binding(s)")

    # Try each binding until we find one with RabbitMQ credentials
    for binding in bindings:
        if 'relationships' in binding and 'app' in binding['relationships']:
            app_guid = binding['relationships']['app']['data']['guid']

            # Get app name for better logging
            app_info = json.loads(run_command(['cf', 'curl', f'/v3/apps/{app_guid}']))
            app_name = app_info.get('name', 'Unknown app')

            print(f"Checking app '{app_name}' for RabbitMQ credentials")

            credentials = extract_rabbitmq_credentials_from_binding(app_guid, service_name)
            if credentials:
                return credentials

    print(f"No valid RabbitMQ credentials found in any app bindings")
    return {}


def check_queue_mirroring(api_uri: str, vhost: str, username: str, password: str) -> List[Dict]:
    """Check for mirrored queues using RabbitMQ HTTP API"""
    try:
        # URL encode the vhost
        import urllib.parse
        encoded_vhost = urllib.parse.quote(vhost, safe='')

        # Get all queues in the vhost
        response = requests.get(
            f"{api_uri}queues/{encoded_vhost}",
            auth=(username, password),
            verify=True
        )
        response.raise_for_status()
        queues = response.json()

        mirrored_queues = []
        for queue in queues:
            # Check if queue has slave nodes (mirrors)
            if queue.get('slave_nodes') and len(queue['slave_nodes']) > 0:
                mirrored_queues.append({
                    'name': queue['name'],
                    'policy': queue.get('policy'),
                    'mirrors': len(queue['slave_nodes']),
                    'synchronized_mirrors': len(queue.get('synchronised_slave_nodes', [])),
                    'policy_definition': queue.get('effective_policy_definition', {})
                })

        return mirrored_queues

    except requests.exceptions.RequestException as e:
        print(f"Error checking queue mirroring: {e}")
        return []


def get_current_target() -> Dict[str, str]:
    """Get current org and space target"""
    try:
        target_output = run_command(['cf', 'target'])
        org = ""
        space = ""

        for line in target_output.splitlines():
            line = line.strip()
            if line.startswith('org:'):
                org = line.split(':', 1)[1].strip()
            elif line.startswith('space:'):
                space = line.split(':', 1)[1].strip()

        return {'org': org, 'space': space}
    except Exception as e:
        print(f"Warning: Could not get current target: {e}")
        return {'org': '', 'space': ''}


def restore_target(target: Dict[str, str]):
    """Restore org and space target"""
    if target['org'] and target['space']:
        try:
            run_command(['cf', 'target', '-o', target['org'], '-s', target['space']])
            print(f"\nRestored target to org: {target['org']}, space: {target['space']}")
        except Exception as e:
            print(f"Warning: Could not restore target: {e}")


def main():
    if not check_cf_auth():
        sys.exit(1)

    # Save current target
    original_target = get_current_target()
    print("Analyzing RabbitMQ instances...")

    try:
        instances = get_service_instances()
        results = []
        instances_without_credentials = []
        total_instances = len(instances)
        instances_with_binding_credentials = 0

        for instance in instances:
            print(f"\nChecking instance: {instance['name']} in {instance['org_name']}/{instance['space_name']}")
            try:
                # First try to get credentials from service keys
                credentials = get_instance_credentials(instance['guid'], instance['org_name'], instance['space_name'])
                credential_source = "service key"

                # If no service keys, try to get credentials from app bindings
                if credentials.get("error") == "no_service_keys":
                    print(f"No service keys available, trying app bindings...")
                    credentials = get_credentials_from_bindings(instance['guid'], instance['org_name'],
                                                                instance['space_name'])
                    if credentials:
                        credential_source = "app binding"
                        instances_with_binding_credentials += 1

                if not credentials:
                    print(f"No credentials found for {instance['name']} (tried both service keys and app bindings)")
                    instances_without_credentials.append(instance)
                    continue

                api_uri = credentials.get('http_api_uri')
                username = credentials.get('username')
                password = credentials.get('password')
                vhost = credentials.get('vhost')

                if not all([api_uri, username, password, vhost]):
                    print(f"Missing required credential information for {instance['name']}")
                    continue

                print(f"Using credentials from {credential_source}")
                mirrored_queues = check_queue_mirroring(api_uri, vhost, username, password)

                if mirrored_queues:
                    results.append({
                        'service_instance': instance['name'],
                        'organization': instance['org_name'],
                        'space': instance['space_name'],
                        'credential_source': credential_source,
                        'mirrored_queues': mirrored_queues
                    })
            except Exception as e:
                print(f"Error processing instance {instance['name']}: {e}")
                continue

        if results:
            print("\nFound instances using classic queue mirroring:")
            print(json.dumps(results, indent=2))
            print("\nSummary:")
            for result in results:
                print(f"\nInstance: {result['service_instance']} in {result['organization']}/{result['space']}")
                print(f"Credentials from: {result['credential_source']}")
                print("Mirrored Queues:")
                for queue in result['mirrored_queues']:
                    print(f"  - Queue: {queue['name']}")
                    print(f"    Policy: {queue['policy']}")
                    print(f"    Mirrors: {queue['mirrors']} ({queue['synchronized_mirrors']} synchronized)")
        else:
            print("\nNo instances found using classic queue mirroring")

        print(f"\nTotal instances processed: {total_instances}")
        print(f"Instances with mirrored queues: {len(results)}")
        print(f"Instances where app bindings provided credentials: {instances_with_binding_credentials}")
        print(f"Instances without any credentials: {len(instances_without_credentials)}")

        if instances_without_credentials:
            print("\nInstances without any credentials:")
            for instance in instances_without_credentials:
                print(f"  - {instance['name']} in {instance['org_name']}/{instance['space_name']}")

    finally:
        # Restore original target
        restore_target(original_target)


if __name__ == '__main__':
    main()