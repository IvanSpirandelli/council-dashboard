# Optional upstream patch — exact LLM token counts

The dashboard approximates token counts as `chars / 4` because the
upstream `ClaudeCodeLLM` (`ml-trainer/ml_trainer/council/llm.py`) only
persists the parsed `structured_output` — it discards the raw `claude
-p` envelope where `usage.input_tokens` / `usage.output_tokens` live.

If you want exact counts displayed in the dashboard, drop this small
patch into ml-trainer. The dashboard auto-detects sidecar
`*.usage.json` files and prefers them over the chars/4 approximation.

## Patch

In `ml-trainer/ml_trainer/council/llm.py` — `ClaudeCodeLLM.chat`,
right before `return validate_response(payload, schema)`:

```python
        # Surface usage to disk via a sidecar that the dashboard reads.
        # See council-dashboard/docs/upstream_patch.md.
        usage = response.get("usage") if isinstance(response, dict) else None
        if usage:
            payload["__usage__"] = usage  # picked up by tracking.append_llm_call
```

Then in `ml-trainer/ml_trainer/tracking.py` — `append_llm_call`, after
the `response_path.write_text(...)` block:

```python
    if isinstance(response, dict) and "__usage__" in response:
        usage_path = response_path.with_suffix(".usage.json")
        usage_path.write_text(json.dumps(response.pop("__usage__"), indent=2))
        # Re-write response without the side-channel field.
        response_path.write_text(json.dumps(response, indent=2, default=str))
```

Both hunks are additive and backwards-compatible: existing rounds
without `__usage__` keep their current shape, and the dashboard
gracefully falls back to the chars/4 estimate when no `*.usage.json`
exists.
