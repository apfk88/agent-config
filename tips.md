# Tips

## exe.dev quick refs
- `ssh exe.dev`
- `ssh exe.dev share show <vmname>`
- `ssh exe.dev share set-public <vmname>` (public, no login)
- `ssh exe.dev share set-private <vmname>` (private)
- `ssh exe.dev share port <vmname> <port>`
- `ssh exe.dev share add <vmname> <email>` (invite by email)
- `ssh exe.dev share remove <vmname> <email>`
- `ssh exe.dev share add-link <vmname>` (shareable link)
- `ssh exe.dev share remove-link <vmname> <token>`

Notes:
- Shared proxy URL: `https://<vmname>.exe.xyz/`.
- `share port` keeps current visibility setting (private by default).
- `share add-link` allows access after login; removing the link does not revoke existing user access.

Docs: https://exe.dev/docs
