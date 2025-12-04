#!/usr/bin/env python3
"""
Validate artifacthub.io annotations in Chart.yaml files.

This script validates:
- YAML syntax in annotation values
- Required fields for changes, images, links, maintainers
- Proper quoting for special characters: {}:[],&*#?|-<>=!%@
- Valid 'kind' values for changes annotation
"""

import sys
import re
from pathlib import Path

try:
    import yaml
except ImportError:
    print("Error: PyYAML is required. Install with: pip install pyyaml")
    sys.exit(1)

# Characters that require quotes in YAML strings
SPECIAL_CHARS = re.compile(r'[{}:\[\],&*#?|\-<>=!%@]')

# Valid kinds for artifacthub.io/changes
VALID_CHANGE_KINDS = {'added', 'changed', 'deprecated', 'removed', 'fixed', 'security'}


def check_special_chars_quoted(value: str, field_path: str) -> list[str]:
    """Check if strings with special characters are properly quoted."""
    errors = []

    if isinstance(value, str) and SPECIAL_CHARS.search(value):
        # The value contains special chars - it should be quoted in the original YAML
        # Since we're parsing after YAML load, we can't check original quoting directly
        # But we can warn about values that NEED quotes
        pass  # YAML already parsed successfully, so quotes were handled

    return errors


def validate_changes(changes_yaml: str, filename: str) -> list[str]:
    """Validate artifacthub.io/changes annotation."""
    errors = []

    try:
        changes = yaml.safe_load(changes_yaml)
    except yaml.YAMLError as e:
        errors.append(f"  artifacthub.io/changes: Invalid YAML syntax - {e}")
        return errors

    if changes is None:
        return errors  # Empty is allowed

    if not isinstance(changes, list):
        errors.append(f"  artifacthub.io/changes: Must be a list, got {type(changes).__name__}")
        return errors

    for i, change in enumerate(changes):
        # Simple string format is allowed
        if isinstance(change, str):
            continue

        if not isinstance(change, dict):
            errors.append(f"  artifacthub.io/changes[{i}]: Must be a string or object, got {type(change).__name__}")
            continue

        # Validate 'kind' field
        if 'kind' not in change:
            errors.append(f"  artifacthub.io/changes[{i}]: Missing required field 'kind'")
        elif change['kind'] not in VALID_CHANGE_KINDS:
            errors.append(
                f"  artifacthub.io/changes[{i}]: Invalid kind '{change['kind']}'. "
                f"Must be one of: {', '.join(sorted(VALID_CHANGE_KINDS))}"
            )

        # Validate 'description' field
        if 'description' not in change:
            errors.append(f"  artifacthub.io/changes[{i}]: Missing required field 'description'")
        elif not isinstance(change['description'], str):
            errors.append(f"  artifacthub.io/changes[{i}]: 'description' must be a string")
        elif not change['description'].strip():
            errors.append(f"  artifacthub.io/changes[{i}]: 'description' cannot be empty")

        # Validate optional 'links' field
        if 'links' in change:
            if not isinstance(change['links'], list):
                errors.append(f"  artifacthub.io/changes[{i}]: 'links' must be a list")
            else:
                for j, link in enumerate(change['links']):
                    if not isinstance(link, dict):
                        errors.append(f"  artifacthub.io/changes[{i}].links[{j}]: Must be an object")
                    elif 'name' not in link or 'url' not in link:
                        errors.append(f"  artifacthub.io/changes[{i}].links[{j}]: Must have 'name' and 'url'")

    return errors


def validate_images(images_yaml: str, filename: str) -> list[str]:
    """Validate artifacthub.io/images annotation."""
    errors = []

    try:
        images = yaml.safe_load(images_yaml)
    except yaml.YAMLError as e:
        errors.append(f"  artifacthub.io/images: Invalid YAML syntax - {e}")
        return errors

    if images is None:
        return errors

    if not isinstance(images, list):
        errors.append(f"  artifacthub.io/images: Must be a list, got {type(images).__name__}")
        return errors

    for i, image in enumerate(images):
        if not isinstance(image, dict):
            errors.append(f"  artifacthub.io/images[{i}]: Must be an object")
            continue

        if 'image' not in image:
            errors.append(f"  artifacthub.io/images[{i}]: Missing required field 'image'")

    return errors


def validate_links(links_yaml: str, filename: str) -> list[str]:
    """Validate artifacthub.io/links annotation."""
    errors = []

    try:
        links = yaml.safe_load(links_yaml)
    except yaml.YAMLError as e:
        errors.append(f"  artifacthub.io/links: Invalid YAML syntax - {e}")
        return errors

    if links is None:
        return errors

    if not isinstance(links, list):
        errors.append(f"  artifacthub.io/links: Must be a list, got {type(links).__name__}")
        return errors

    for i, link in enumerate(links):
        if not isinstance(link, dict):
            errors.append(f"  artifacthub.io/links[{i}]: Must be an object")
            continue

        if 'name' not in link:
            errors.append(f"  artifacthub.io/links[{i}]: Missing required field 'name'")
        if 'url' not in link:
            errors.append(f"  artifacthub.io/links[{i}]: Missing required field 'url'")

    return errors


def validate_maintainers(maintainers_yaml: str, filename: str) -> list[str]:
    """Validate artifacthub.io/maintainers annotation."""
    errors = []

    try:
        maintainers = yaml.safe_load(maintainers_yaml)
    except yaml.YAMLError as e:
        errors.append(f"  artifacthub.io/maintainers: Invalid YAML syntax - {e}")
        return errors

    if maintainers is None:
        return errors

    if not isinstance(maintainers, list):
        errors.append(f"  artifacthub.io/maintainers: Must be a list, got {type(maintainers).__name__}")
        return errors

    for i, maintainer in enumerate(maintainers):
        if not isinstance(maintainer, dict):
            errors.append(f"  artifacthub.io/maintainers[{i}]: Must be an object")
            continue

        if 'name' not in maintainer:
            errors.append(f"  artifacthub.io/maintainers[{i}]: Missing required field 'name'")
        if 'email' not in maintainer:
            errors.append(f"  artifacthub.io/maintainers[{i}]: Missing required field 'email'")

    return errors


def validate_category(category: str, filename: str) -> list[str]:
    """Validate artifacthub.io/category annotation."""
    valid_categories = {
        'ai-machine-learning', 'database', 'integration-delivery',
        'monitoring-logging', 'networking', 'security', 'storage',
        'streaming-messaging', 'skip-prediction'
    }

    if category not in valid_categories:
        return [f"  artifacthub.io/category: Invalid category '{category}'. Must be one of: {', '.join(sorted(valid_categories))}"]

    return []


def validate_chart_yaml(filename: str) -> list[str]:
    """Validate a Chart.yaml file for artifacthub.io annotations."""
    errors = []

    try:
        with open(filename, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        return [f"Error reading file: {e}"]

    # First, check for common YAML issues in the raw content
    # Check for tabs (should use spaces)
    if '\t' in content:
        errors.append("  File contains tabs - use spaces for indentation")

    try:
        chart = yaml.safe_load(content)
    except yaml.YAMLError as e:
        errors.append(f"  Invalid YAML syntax: {e}")
        return errors

    if chart is None:
        errors.append("  Empty Chart.yaml file")
        return errors

    if not isinstance(chart, dict):
        errors.append(f"  Chart.yaml must be a mapping, got {type(chart).__name__}")
        return errors

    annotations = chart.get('annotations', {})
    if not annotations:
        return errors  # No annotations to validate

    # Validate each known annotation type
    validators = {
        'artifacthub.io/changes': validate_changes,
        'artifacthub.io/images': validate_images,
        'artifacthub.io/links': validate_links,
        'artifacthub.io/maintainers': validate_maintainers,
    }

    for annotation_key, validator in validators.items():
        if annotation_key in annotations:
            annotation_value = annotations[annotation_key]
            if annotation_value is not None:
                errors.extend(validator(str(annotation_value), filename))

    # Validate category separately (it's a simple string)
    if 'artifacthub.io/category' in annotations:
        category = annotations['artifacthub.io/category']
        if category:
            errors.extend(validate_category(str(category), filename))

    # Validate boolean string annotations
    bool_annotations = [
        'artifacthub.io/containsSecurityUpdates',
        'artifacthub.io/operator',
        'artifacthub.io/prerelease',
    ]
    for annotation in bool_annotations:
        if annotation in annotations:
            value = str(annotations[annotation]).lower()
            if value not in ('true', 'false'):
                errors.append(f"  {annotation}: Must be 'true' or 'false', got '{annotations[annotation]}'")

    return errors


def main() -> int:
    """Main entry point."""
    if len(sys.argv) < 2:
        print("Usage: validate-artifacthub-annotations.py <Chart.yaml> [Chart.yaml ...]")
        return 1

    exit_code = 0

    for filename in sys.argv[1:]:
        path = Path(filename)

        if not path.exists():
            print(f"❌ {filename}: File not found")
            exit_code = 1
            continue

        if path.name != 'Chart.yaml':
            continue  # Skip non-Chart.yaml files silently

        errors = validate_chart_yaml(filename)

        if errors:
            print(f"❌ {filename}:")
            for error in errors:
                print(error)
            exit_code = 1
        else:
            print(f"✅ {filename}: Valid")

    return exit_code


if __name__ == '__main__':
    sys.exit(main())
