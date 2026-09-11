"""Base64 sorted-keys JSON envelopes (`mesh_request` / `mesh_receipt`).

Signatures cover the newline-joined signing inputs, not envelope bytes, so
cross-platform compatibility requires sorted keys and lossless values — not
byte-identical JSON escaping.
"""

import base64
import json

from meshkit.trust import MeshValidationError


def encode(obj: dict) -> str:
    data = json.dumps(obj, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
    return base64.b64encode(data.encode("utf-8")).decode("ascii")


def decode(encoded: str, what: str) -> dict:
    try:
        data = base64.b64decode(encoded, validate=True)
    except Exception:
        raise MeshValidationError("invalid_encoding", f"{what} is not valid base64")
    try:
        obj = json.loads(data.decode("utf-8"))
    except Exception:
        raise MeshValidationError("invalid_encoding", f"{what} is not valid JSON")
    if not isinstance(obj, dict):
        raise MeshValidationError("invalid_encoding", f"{what} root is not an object")
    return obj


def require_str(obj: dict, key: str, what: str) -> str:
    value = obj.get(key)
    if not isinstance(value, str):
        raise MeshValidationError("invalid_encoding", f"{what}.{key} is not a string")
    return value


def require_str_map(obj: dict, key: str, what: str) -> dict[str, str]:
    value = obj.get(key)
    if not isinstance(value, dict):
        raise MeshValidationError("invalid_encoding", f"{what}.{key} is not an object")
    out: dict[str, str] = {}
    for k, v in value.items():
        if not isinstance(v, str):
            raise MeshValidationError("invalid_encoding", f"{what}.{key}[{k}] is not a string")
        out[k] = v
    return out


def require_obj(obj: dict, key: str, what: str) -> dict:
    value = obj.get(key)
    if not isinstance(value, dict):
        raise MeshValidationError("invalid_encoding", f"{what}.{key} is not an object")
    return value
