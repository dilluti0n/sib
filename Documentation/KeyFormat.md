# Reserved keys

Sib trace format. Follows [Open
Responses](https://www.openresponses.org/specification) item fields
except `sib:` prefixed keys (for metadata).

| key                 | meaning                                                           |
|---------------------|-------------------------------------------------------------------|
| `type`              | `message` (default), `function_call`, `function_call_output`, `reasoning` |
| `content`           | Payload: message text, call arguments, call output, reasoning summary |
| `role`              | `message` only. `user`, `assistant`, `system`, `developer` |
| `call_id`           | `function_call`, `function_call_output`. Pairs a call with its output |
| `name`              | `function_call`. Function name                                    |
| `encrypted_content` | `reasoning`. Opaque, passed back as is                            |
| `id`                | `reasoning`. Item id, passed back with `encrypted_content`        |
| `status`            | Present only when not `completed`                                 |
