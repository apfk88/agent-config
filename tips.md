# Tips

## tm (agent-config)
- `tm new [path|url] [branch]` or `tm new org/repo#branch`
- `tm attach` (pick a session)
- `tm list`, `tm kill`, `tm rename <new>`, `tm help`
- Session name = repo folder

## tmux basics
- Prefix: `Ctrl-b`
- Windows: `c` new, `w` list, `n/p` next/prev, `,` rename, `&` kill
- Panes: `"` split, `%` split vertical, `o` next, `x` kill
- Sessions: `d` detach, `s` list

## exe.dev quick refs
- `ssh exe.dev`
- `ssh exe.dev share show <vmname>`
- `ssh exe.dev share set-public <vmname>`
- `ssh exe.dev share set-private <vmname>`
- `ssh exe.dev share port <vmname> <port>`
- `ssh exe.dev share add <vmname> <email>`
- `ssh exe.dev share remove <vmname> <email>`
- `ssh exe.dev share add-link <vmname>`
- `ssh exe.dev share remove-link <vmname> <token>`

Notes:
- Shared proxy URL: `https://<vmname>.exe.xyz/`.
- `share port` keeps current visibility setting.
- `share add-link` creates a shareable link; removing it won’t revoke existing user access.

Docs: https://exe.dev/docs
