# Planted issue: hardcoded OpenAI API key with prefix that matches scan_secrets.sh.
# This file should be flagged by auditor-static.

OPENAI_API_KEY = "sk-proj-abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGHIJKL"
ANTHROPIC_API_KEY = "sk-ant-api03-abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGH"

def get_key():
    return OPENAI_API_KEY
