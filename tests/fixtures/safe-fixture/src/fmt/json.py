# Near-miss: package-internal module; absolute imports keep stdlib json first.
import json as _json


def dumps(obj):
    return _json.dumps(obj, sort_keys=True)
