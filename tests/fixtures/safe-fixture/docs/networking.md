# Local networking notes

Example private addresses used in documentation only. These are RFC1918 / link-local
and must NOT be reported as exfiltration destinations by scan_network:

- Router on the LAN: `192.168.1.1`
- A host in the private range: `10.0.0.5`
- Docker bridge gateway: `172.17.0.1`

## Authenticating to the local dev API

Send the token in the standard header. The value below is a placeholder, not a real
credential, and must NOT be reported by scan_secrets:

```
Authorization: Bearer YOUR_API_TOKEN_PLACEHOLDER_VALUE_HERE
```
