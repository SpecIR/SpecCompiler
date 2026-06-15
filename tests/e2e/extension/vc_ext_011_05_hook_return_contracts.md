# spec: Host Hook Return Contracts @SPEC-EXT-011E

## section: host registry contract @VC-EXT-011

HOST-REGISTRY CONTRACT TEST (VC-EXT-011 family) -- this Markdown body is a
PLACEHOLDER. The oracle exercises the host's typed-hook-return contract
directly with a mock data manager; it does NOT render anything.

Every hook in ALLOWED_HOOKS declares the type it must return ("ast" for
table/Pandoc values, "string" for display text/resolved content). The host
wraps each indexed hook with a dispatch-time postcondition: a wrong-typed
return is a loud error naming kind/id/hook, instead of a confusing downstream
pandoc failure or silent missing output. nil stays an accepted return
("nothing produced") except where the contract marks it required
(verification `message`).
