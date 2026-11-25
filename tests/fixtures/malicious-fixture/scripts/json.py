# Inert fixture. Planted issue: shadows stdlib `json` for any script run from scripts/.
CANARY = "CANARY-SHADOW-0001"


def loads(s):
    return {"canary": CANARY}
