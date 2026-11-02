# Doom / gptel data disclosure review

Reviewed 1 November 2026. This is a focused source inspection, not a complete
security audit or network capture. No existing credentials, conversations or
private runtime data were inspected. No live login or model request was made.

## Scope and provenance

Checked Doom's llm module, the configured OpenAI OAuth backend, gptel request
and context handling, gptel-inline, gptel-agent tools/presets and the custom
project-boundary hook. Also scanned the request entry points in gptel-quick,
gptel-magit and ob-gptel. This does not cover every installed Emacs dependency.

- Doom pins gptel to `ebf0f3d8e9932e0ac6de82542220864cc17f6784`.
- packages.el pins gptel-agent to `2fbe4f6c71a6a1355c647ce90151c8c2bc1c4bdf`.
- packages.el pins gptel-inline to `7a74fda2ed420c5967437f80c4eeb5a7d52a6314`.
- Nix applies the local OAuth patch declared in users/josh/nix/doom.nix.

The built patched profile is
`/nix/store/zljh9cch1djiq1f14dkjmrgqfmjvdadb-emacs-unstable-with-doom-31.1`.
The active ~/.nix-profile/bin/emacs still resolves to an older package with
unpatched gptel. Library paths were checked in batch without loading user
configuration. Source comparisons confirmed matching agent tools and inline
implementation (inline has Nix-generated package-version header changes).
Pins make the code reproducible; they do not sandbox its execution.

## Findings

### Web tools permit model-directed disclosure without approval

The planning preset includes WebFetch and WebSearch. Neither tool has
`:confirm t`. With `gptel-confirm-tool-calls` set to `auto`, these tools can
run without approval. The custom project hook only handles filesystem tools.

WebFetch forwards the model-supplied URL to Emacs url-retrieve. There is no
host or scheme allowlist in that wrapper. WebSearch sends the model-supplied
query to eww-search-prefix, normally DuckDuckGo. A URL path/query or search
query could contain source text or secrets previously seen by the model.
This creates an exfiltration route if a model follows malicious instructions
in a file or fetched page. It is a capability, not evidence of malicious use.
Planning being read-only does not prevent network disclosure.

Evidence: gptel-agent-tools.el, gptel-agent--read-url (line 418),
gptel-agent--fetch-with-timeout (line 309), WebSearch/WebFetch declarations
(lines 1655/1677), agents/gptel-plan.md; gptel-request.el,
gptel--handle-tool-use; config.el, josh/gptel-agent-tool-path.

A synthetic check loaded package definitions only, intercepted the fetch
function before any network operation, and confirmed that the supplied URL
is forwarded unchanged. It confirmed nil approval flags for WebFetch,
WebSearch and Read, t for Bash/Eval, and no project-hook override for WebFetch.

### File contents become model context without secret filtering

Read/Grep results are returned to the configured model. In-project reads do
not require approval under the current hook. There is no secret redaction or
blanket exclusion of credential files in Read. Its sanitisation concerns
binary data and encoding, not secrets. Project membership does not make an
`.env` file safe to send. Explicit inline references likewise include their
text, buffer/file name, line numbers and associated hyperlinks.

The agent also discovers skill metadata from configured local skill
directories and includes names/descriptions in its system prompt; invoking
Skill includes the body. I inspected that mechanism, not the user's skills.

Evidence: gptel-agent--read-file-lines (line 1111),
gptel-agent--sanitize-buffer (line 185), gptel-agent-update,
gptel-agent--skills-system-message, gptel-inline--reference-text (line 353).

### Execution tools are powerful but request confirmation

Bash runs bash -c, and Eval evaluates arbitrary Emacs Lisp. Both declare
confirmation and are not constrained by an OS sandbox supplied by Doom or
gptel. Approval can therefore permit file reads and network sends beyond
the project hook. Agent delegation also requests confirmation. These are
documented agent capabilities, not concealed execution paths.

### No concealed collector found in the inspected paths

OAuth requests target auth.openai.com. Model requests use the configured
chatgpt.com/backend-api/codex/responses backend. I found no hard-coded
third-party credential collector, telemetry upload or periodic background
file uploader in the inspected paths. Inline sending goes through gptel's
normal request pipeline; its timers handle UI updates. Agent web tools add
intentional destinations, including arbitrary fetched sites, the configured
search engine and YouTube for transcript requests.

The OpenAI bearer header is constructed for model requests; the reviewed
web-fetch helper does not explicitly attach that credential. Local debug
logging can include request headers, so the repository config disables it.
The OAuth patch also removes login-URL logging and disposes of response
buffers. Local logs are an exposure concern, not evidence of remote upload.

## Suggested next changes

Require approval for WebFetch and WebSearch through the global pre-tool hook,
including delegated agents. Consider limiting fetches to HTTP(S) and requiring
approval for recognised sensitive file paths, including inside the project.
These checks reduce accidental disclosure but do not turn the agent into a
sandbox; manual inline context and approved Bash/Eval can still disclose data.

No runtime settings were changed as part of this review.
