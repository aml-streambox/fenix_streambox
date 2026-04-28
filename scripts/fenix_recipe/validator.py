from __future__ import annotations

from dataclasses import dataclass
import json
from json import JSONDecodeError
from pathlib import Path
import re
from typing import Any


RECIPE_SCHEMA = "fenix.recipe.v1"
RECIPE_NAME_RE = re.compile(r"^[a-z0-9][a-z0-9+._-]*$")
ARCH_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
SHA256_RE = re.compile(r"^[A-Fa-f0-9]{64}$")
MODE_RE = re.compile(r"^[0-7]{3,4}$")
SERVICE_RE = re.compile(r"^[A-Za-z0-9_.@:+-]+\.(service|socket|timer|path|target)$")

TOP_LEVEL_KEYS = {
    "schema",
    "name",
    "version",
    "summary",
    "license",
    "source",
    "patches",
    "build",
    "dependencies",
    "outputs",
    "vendor_blob",
    "metadata",
}
SOURCE_KEYS = {"type", "uri", "path", "revision", "sha256", "subdir"}
BUILD_KEYS = {"class", "env", "configure_args", "build_args", "install_args", "targets", "install_target", "offline", "locked"}
DEPENDENCY_KEYS = {"recipes", "distro_dev", "native_tools"}
OUTPUT_KEYS = {
    "package",
    "architecture",
    "section",
    "priority",
    "description",
    "runtime_depends",
    "files",
    "sysroot_exports",
    "services",
    "kernel_modules",
}
FILE_MAPPING_KEYS = {"from", "to", "mode"}
SERVICE_KEYS = {"unit", "enable"}
KERNEL_MODULE_KEYS = {"path", "autoload", "options", "udev_rules"}
VENDOR_BLOB_KEYS = {
    "origin",
    "version",
    "sha256",
    "license_category",
    "reason_source_unavailable",
    "replacement",
}
REPLACEMENT_KEYS = {"owner", "status"}

SOURCE_TYPES = {"git", "tarball", "local", "vendor-blob"}
BUILD_CLASSES = {"make", "cmake", "meson", "cargo", "kernel-module", "vendor-blob"}


@dataclass(frozen=True)
class ValidationIssue:
    location: str
    message: str


def validate_recipe_file(path: Path) -> list[ValidationIssue]:
    try:
        with path.open("r", encoding="utf-8") as recipe_file:
            data = json.load(recipe_file)
    except FileNotFoundError:
        return [ValidationIssue("$", "file does not exist")]
    except JSONDecodeError as exc:
        return [ValidationIssue("$", f"invalid JSON: {exc.msg} at line {exc.lineno}, column {exc.colno}")]
    except OSError as exc:
        return [ValidationIssue("$", f"cannot read file: {exc}")]

    return validate_recipe(data)


def validate_recipe(data: Any) -> list[ValidationIssue]:
    issues: list[ValidationIssue] = []
    if not isinstance(data, dict):
        return [ValidationIssue("$", "recipe must be a JSON object")]

    _check_required(data, ["schema", "name", "version", "summary", "license", "source", "build", "dependencies", "outputs"], "$", issues)
    _check_unknown(data, TOP_LEVEL_KEYS, "$", issues)

    _check_literal(data, "schema", RECIPE_SCHEMA, "$.schema", issues)
    _check_string(data, "name", "$.name", issues, pattern=RECIPE_NAME_RE)
    _check_string(data, "version", "$.version", issues)
    _check_string(data, "summary", "$.summary", issues)
    _check_string(data, "license", "$.license", issues)
    _check_string_list(data, "patches", "$.patches", issues, required=False)
    _check_object(data, "metadata", "$.metadata", issues, required=False)

    source = _check_object(data, "source", "$.source", issues)
    if source is not None:
        _validate_source(source, issues)

    build = _check_object(data, "build", "$.build", issues)
    if build is not None:
        _validate_build(build, issues)

    dependencies = _check_object(data, "dependencies", "$.dependencies", issues)
    if dependencies is not None:
        _validate_dependencies(dependencies, issues)

    outputs = _check_array(data, "outputs", "$.outputs", issues)
    if outputs is not None:
        if not outputs:
            issues.append(ValidationIssue("$.outputs", "must contain at least one package output"))
        seen_packages: set[str] = set()
        for index, output in enumerate(outputs):
            if not isinstance(output, dict):
                issues.append(ValidationIssue(f"$.outputs[{index}]", "must be an object"))
                continue
            _validate_output(output, f"$.outputs[{index}]", issues)
            package = output.get("package")
            if isinstance(package, str):
                if package in seen_packages:
                    issues.append(ValidationIssue(f"$.outputs[{index}].package", f"duplicate output package '{package}'"))
                seen_packages.add(package)

    needs_vendor_blob = False
    if isinstance(source, dict) and source.get("type") == "vendor-blob":
        needs_vendor_blob = True
    if isinstance(build, dict) and build.get("class") == "vendor-blob":
        needs_vendor_blob = True

    vendor_blob = _check_object(data, "vendor_blob", "$.vendor_blob", issues, required=needs_vendor_blob)
    if vendor_blob is not None:
        _validate_vendor_blob(vendor_blob, issues)

    return issues


def _validate_source(source: dict[str, Any], issues: list[ValidationIssue]) -> None:
    _check_required(source, ["type"], "$.source", issues)
    _check_unknown(source, SOURCE_KEYS, "$.source", issues)
    source_type = source.get("type")
    if not isinstance(source_type, str):
        issues.append(ValidationIssue("$.source.type", "must be a string"))
        return
    if source_type not in SOURCE_TYPES:
        issues.append(ValidationIssue("$.source.type", f"must be one of: {', '.join(sorted(SOURCE_TYPES))}"))
        return

    if source_type == "git":
        _check_required(source, ["uri", "revision"], "$.source", issues)
    elif source_type == "tarball":
        _check_required(source, ["uri", "sha256"], "$.source", issues)
    elif source_type == "local":
        _check_required(source, ["path"], "$.source", issues)
    elif source_type == "vendor-blob":
        if "uri" not in source and "path" not in source:
            issues.append(ValidationIssue("$.source", "vendor-blob source requires uri or path"))
        _check_required(source, ["sha256"], "$.source", issues)

    _check_string(source, "uri", "$.source.uri", issues, required=False)
    _check_string(source, "path", "$.source.path", issues, required=False)
    _check_string(source, "revision", "$.source.revision", issues, required=False)
    _check_string(source, "subdir", "$.source.subdir", issues, required=False)
    _check_string(source, "sha256", "$.source.sha256", issues, required=False, pattern=SHA256_RE)


def _validate_build(build: dict[str, Any], issues: list[ValidationIssue]) -> None:
    _check_required(build, ["class"], "$.build", issues)
    _check_unknown(build, BUILD_KEYS, "$.build", issues)
    build_class = build.get("class")
    if not isinstance(build_class, str):
        issues.append(ValidationIssue("$.build.class", "must be a string"))
    elif build_class not in BUILD_CLASSES:
        issues.append(ValidationIssue("$.build.class", f"must be one of: {', '.join(sorted(BUILD_CLASSES))}"))

    env = _check_object(build, "env", "$.build.env", issues, required=False)
    if env is not None:
        for key, value in env.items():
            if not isinstance(value, str):
                issues.append(ValidationIssue(f"$.build.env.{key}", "must be a string"))

    for key in ("configure_args", "build_args", "install_args", "targets"):
        _check_string_list(build, key, f"$.build.{key}", issues, required=False)
    _check_string(build, "install_target", "$.build.install_target", issues, required=False)
    _check_bool(build, "offline", "$.build.offline", issues, required=False)
    _check_bool(build, "locked", "$.build.locked", issues, required=False)


def _validate_dependencies(dependencies: dict[str, Any], issues: list[ValidationIssue]) -> None:
    _check_unknown(dependencies, DEPENDENCY_KEYS, "$.dependencies", issues)
    for key in ("recipes", "distro_dev", "native_tools"):
        _check_string_list(dependencies, key, f"$.dependencies.{key}", issues, required=False)


def _validate_output(output: dict[str, Any], location: str, issues: list[ValidationIssue]) -> None:
    _check_required(output, ["package", "architecture", "description", "files"], location, issues)
    _check_unknown(output, OUTPUT_KEYS, location, issues)
    _check_string(output, "package", f"{location}.package", issues, pattern=RECIPE_NAME_RE)
    _check_string(output, "architecture", f"{location}.architecture", issues, pattern=ARCH_RE)
    _check_string(output, "section", f"{location}.section", issues, required=False)
    _check_string(output, "priority", f"{location}.priority", issues, required=False)
    _check_string(output, "description", f"{location}.description", issues)
    _check_string_list(output, "runtime_depends", f"{location}.runtime_depends", issues, required=False)

    for key in ("files", "sysroot_exports"):
        mappings = _check_array(output, key, f"{location}.{key}", issues, required=(key == "files"))
        if mappings is None:
            continue
        for index, mapping in enumerate(mappings):
            mapping_location = f"{location}.{key}[{index}]"
            if not isinstance(mapping, dict):
                issues.append(ValidationIssue(mapping_location, "must be an object"))
                continue
            _validate_file_mapping(mapping, mapping_location, issues)

    services = _check_array(output, "services", f"{location}.services", issues, required=False)
    if services is not None:
        for index, service in enumerate(services):
            service_location = f"{location}.services[{index}]"
            if not isinstance(service, dict):
                issues.append(ValidationIssue(service_location, "must be an object"))
                continue
            _validate_service(service, service_location, issues)

    modules = _check_array(output, "kernel_modules", f"{location}.kernel_modules", issues, required=False)
    if modules is not None:
        for index, module in enumerate(modules):
            module_location = f"{location}.kernel_modules[{index}]"
            if not isinstance(module, dict):
                issues.append(ValidationIssue(module_location, "must be an object"))
                continue
            _validate_kernel_module(module, module_location, issues)


def _validate_file_mapping(mapping: dict[str, Any], location: str, issues: list[ValidationIssue]) -> None:
    _check_required(mapping, ["from", "to"], location, issues)
    _check_unknown(mapping, FILE_MAPPING_KEYS, location, issues)
    _check_string(mapping, "from", f"{location}.from", issues)
    destination = mapping.get("to")
    if not isinstance(destination, str):
        issues.append(ValidationIssue(f"{location}.to", "must be a string"))
    elif not destination.startswith("/"):
        issues.append(ValidationIssue(f"{location}.to", "must be an absolute package path"))
    _check_string(mapping, "mode", f"{location}.mode", issues, required=False, pattern=MODE_RE)


def _validate_service(service: dict[str, Any], location: str, issues: list[ValidationIssue]) -> None:
    _check_required(service, ["unit"], location, issues)
    _check_unknown(service, SERVICE_KEYS, location, issues)
    _check_string(service, "unit", f"{location}.unit", issues, pattern=SERVICE_RE)
    enable = service.get("enable")
    if enable is not None and not isinstance(enable, bool):
        issues.append(ValidationIssue(f"{location}.enable", "must be a boolean"))


def _validate_kernel_module(module: dict[str, Any], location: str, issues: list[ValidationIssue]) -> None:
    _check_required(module, ["path"], location, issues)
    _check_unknown(module, KERNEL_MODULE_KEYS, location, issues)
    path = module.get("path")
    if not isinstance(path, str):
        issues.append(ValidationIssue(f"{location}.path", "must be a string"))
    elif not path.startswith("/lib/modules/") or not path.endswith(".ko"):
        issues.append(ValidationIssue(f"{location}.path", "must be an absolute /lib/modules/.../*.ko path"))
    _check_string(module, "autoload", f"{location}.autoload", issues, required=False)
    _check_string(module, "options", f"{location}.options", issues, required=False)
    _check_string_list(module, "udev_rules", f"{location}.udev_rules", issues, required=False)


def _validate_vendor_blob(vendor_blob: dict[str, Any], issues: list[ValidationIssue]) -> None:
    _check_required(
        vendor_blob,
        ["origin", "version", "sha256", "license_category", "reason_source_unavailable", "replacement"],
        "$.vendor_blob",
        issues,
    )
    _check_unknown(vendor_blob, VENDOR_BLOB_KEYS, "$.vendor_blob", issues)
    _check_string(vendor_blob, "origin", "$.vendor_blob.origin", issues)
    _check_string(vendor_blob, "version", "$.vendor_blob.version", issues)
    _check_string(vendor_blob, "sha256", "$.vendor_blob.sha256", issues, pattern=SHA256_RE)
    _check_string(vendor_blob, "license_category", "$.vendor_blob.license_category", issues)
    _check_string(vendor_blob, "reason_source_unavailable", "$.vendor_blob.reason_source_unavailable", issues)

    replacement = _check_object(vendor_blob, "replacement", "$.vendor_blob.replacement", issues)
    if replacement is not None:
        _check_required(replacement, ["owner", "status"], "$.vendor_blob.replacement", issues)
        _check_unknown(replacement, REPLACEMENT_KEYS, "$.vendor_blob.replacement", issues)
        _check_string(replacement, "owner", "$.vendor_blob.replacement.owner", issues)
        _check_string(replacement, "status", "$.vendor_blob.replacement.status", issues)


def _check_required(data: dict[str, Any], keys: list[str], location: str, issues: list[ValidationIssue]) -> None:
    for key in keys:
        if key not in data:
            issues.append(ValidationIssue(location, f"missing required field '{key}'"))


def _check_unknown(data: dict[str, Any], allowed: set[str], location: str, issues: list[ValidationIssue]) -> None:
    for key in sorted(set(data) - allowed):
        issues.append(ValidationIssue(f"{location}.{key}", "unknown field"))


def _check_literal(data: dict[str, Any], key: str, expected: str, location: str, issues: list[ValidationIssue]) -> None:
    if key not in data:
        return
    if data[key] != expected:
        issues.append(ValidationIssue(location, f"must be '{expected}'"))


def _check_string(
    data: dict[str, Any],
    key: str,
    location: str,
    issues: list[ValidationIssue],
    *,
    required: bool = True,
    pattern: re.Pattern[str] | None = None,
) -> str | None:
    if key not in data:
        if required:
            issues.append(ValidationIssue(location.rsplit(".", 1)[0], f"missing required field '{key}'"))
        return None
    value = data[key]
    if not isinstance(value, str):
        issues.append(ValidationIssue(location, "must be a string"))
        return None
    if not value:
        issues.append(ValidationIssue(location, "must not be empty"))
    if pattern is not None and not pattern.match(value):
        issues.append(ValidationIssue(location, "has invalid format"))
    return value


def _check_object(
    data: dict[str, Any],
    key: str,
    location: str,
    issues: list[ValidationIssue],
    *,
    required: bool = True,
) -> dict[str, Any] | None:
    if key not in data:
        if required:
            issues.append(ValidationIssue(location.rsplit(".", 1)[0], f"missing required field '{key}'"))
        return None
    value = data[key]
    if not isinstance(value, dict):
        issues.append(ValidationIssue(location, "must be an object"))
        return None
    return value


def _check_array(
    data: dict[str, Any],
    key: str,
    location: str,
    issues: list[ValidationIssue],
    *,
    required: bool = True,
) -> list[Any] | None:
    if key not in data:
        if required:
            issues.append(ValidationIssue(location.rsplit(".", 1)[0], f"missing required field '{key}'"))
        return None
    value = data[key]
    if not isinstance(value, list):
        issues.append(ValidationIssue(location, "must be an array"))
        return None
    return value


def _check_string_list(
    data: dict[str, Any],
    key: str,
    location: str,
    issues: list[ValidationIssue],
    *,
    required: bool = True,
) -> None:
    values = _check_array(data, key, location, issues, required=required)
    if values is None:
        return
    for index, value in enumerate(values):
        if not isinstance(value, str):
            issues.append(ValidationIssue(f"{location}[{index}]", "must be a string"))
        elif not value:
            issues.append(ValidationIssue(f"{location}[{index}]", "must not be empty"))


def _check_bool(
    data: dict[str, Any],
    key: str,
    location: str,
    issues: list[ValidationIssue],
    *,
    required: bool = True,
) -> bool | None:
    if key not in data:
        if required:
            issues.append(ValidationIssue(location.rsplit(".", 1)[0], f"missing required field '{key}'"))
        return None
    value = data[key]
    if not isinstance(value, bool):
        issues.append(ValidationIssue(location, "must be a boolean"))
        return None
    return value
