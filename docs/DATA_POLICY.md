# Local data and privacy contract

`resources/data_policy.json` is the machine-readable contract for the current build. It records every persistent dataset, whether creation is automatic or user initiated, its local `user://` destination, and its bounded retention. `tools/data_policy_audit.py` verifies that those paths and limits still match the implementation.

The current product contract is deliberately offline:

- no gameplay, diagnostic, identity, hardware, or account data is transmitted;
- no online telemetry or networking API is present in production GDScript;
- settings, progression, campaign records, replays, and the session journal stay on the local device;
- playtest and diagnostic JSON files are created only when the player selects the corresponding Combat Archive action;
- the session journal infers a missing clean-exit marker and is not represented as a native crash dump;
- each session records only the non-player release candidate ID needed to associate a manual diagnostic with the exact build; v1 journals migrate to v2 with `legacy_unknown` for older entries;
- English and Korean in-build disclosures describe the same behavior.

The static source scan is a change detector, not a legal opinion or packet-level certification. Adding online leaderboards, crash upload, telemetry, account services, or any other network feature requires a reviewed policy/schema revision, consent design where applicable, security assessment, updated in-build disclosure, and new transport-level tests. `external_legal_review` must remain `pending` until qualified review evidence exists.
