# Mapped Storage: Azure Key Vault

This is the activity contract implemented by `Storage_AzureKeyVault`. The module's provider-free tests establish request/result routing; live vault behavior is a separate acceptance boundary. `Storage_AzureKeyVault` supports `Read`, `Write`, `Delete`, `Exists`, and metadata-only `List` through mapped Storage. It does not implement file transfer (`SourcePath`, `TargetPath`, binary content, or file result detail), per-version deletion, recovery, or purge.

The supplied mapped `Activity` selects the operation. `Config.VirtualPath` has precedence and may be a raw secret name. The legacy `Storage.Secrets.Read.<name>` form is accepted only for Read. Otherwise the mapped wrapper's `Container/Resource` synthesis must yield `/name` with empty Container. A secret name is 1–127 alphanumeric/hyphen characters. Version suffixes, paths, query strings and encoded separators are rejected before a request. The v2 jacket has `SchemaVersion:2`, one `Routes` entry `{Key:'primary',Address:'https://<vault>.vault.azure.net/',ResourceKey:'vault'}` and one `Resource` entry `{Key:'vault',Vault:'<vault>'}`; the selected route host must match the named vault. Real v1 jackets retain their legacy address projection.

| Activity | Success Result | Failure/limits |
| --- | --- | --- |
| Read | Raw string value from HTTP 200. A plan step's `Format:'Json'` parses a JSON value after mapped dispatch. | Missing value, 404, denied or ambiguous status fail. Read Result is sensitive in memory; do not serialize it to diagnostics. |
| Write | Versioned same-vault secret URI from HTTP 200. Each successful set creates a version. | `Config.Content` must be string (empty allowed) or JSON object/array serialized once; the UTF-8 secret value is limited to 25 KB. File/binary input and invalid response id fail. |
| Delete | Native `true` on accepted HTTP 200 response. | Soft-deletes all versions without purge; a deleted name may remain reserved. Missing/denied/ambiguous calls fail. |
| Exists | Native `true` on HTTP 200, `false` only on exact-name HTTP 404. | 401/403/429/5xx and malformed status fail rather than report absence. |
| List | `{Items,Count}` with FileName, VirtualPath, DateTime and null Size metadata; never values. | Invalid pagination/continuation fails atomically; Directory returns an empty list. |

Only successful Read/underlying REST `Signal.Result` carries a value to the authorized consumer. Diagnostic Signal messages, error merges and test evidence must not contain secret values. The REST status envelope is `{Response,StatusCode}` when `ReturnHttpStatus:true`; `Success` alone is not an HTTP success oracle. With a status-mode body-bearing PUT, the REST core captures `StatusCode` explicitly. Synthetic nonsecret fixtures may appear in expected test output. Provider-free source checks cannot establish a live principal's permissions or durable persistence.
