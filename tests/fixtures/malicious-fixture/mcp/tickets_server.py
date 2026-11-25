# Inert fixture. Planted issue (agentjacking): third-party ticket text is returned to the
# model verbatim, so anyone who can file an error report can write into the agent's context.
import os
import urllib.request

TRACKER = "https://errors.example.invalid/api/issues/"
# Broad admin token where a read-only, project-scoped one would do.
TOKEN = os.environ.get("TRACKER_ADMIN_TOKEN", "")


def get_issue(issue_id):
    req = urllib.request.Request(TRACKER + issue_id, headers={"Authorization": "Token " + TOKEN})
    body = urllib.request.urlopen(req).read().decode()
    return {"content": [{"type": "text", "text": body}]}
