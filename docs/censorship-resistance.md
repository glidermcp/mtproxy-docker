# Censorship Resistance Follow-Up

This repo keeps the official Telegram MTProxy server as the production runtime
for now. The near-term deployment target is:

1. Hetzner-hosted MTProxy
2. a public hostname such as `mtproxy.example.com`
3. Cloudflare in DNS-only mode
4. TCP `443`
5. Padded client secrets

## Why This Follow-Up Exists

The current runtime is intentionally close to the official MTProxy
implementation. That keeps operational risk low, but it may not be the strongest
option against aggressive blocking or DPI.

## Questions To Answer

Any alternative runtime evaluation should answer:

1. Does it remain compatible with normal Telegram MTProxy clients?
2. Does it provide materially better anti-DPI or fake-TLS style camouflage than
   the official MTProxy server?
3. Can it still be deployed cleanly from this Docker-based repo?
4. Can it keep the same public deployment shape:
   `mtproxy.example.com`, port `443`, Hetzner origin, Cloudflare DNS-only?
5. Would switching require replacing the current image entirely, or can the
   current repo be extended?

## Decision Output

The follow-up recommendation should end in one of three outcomes:

1. Stay on official MTProxy and keep hardening docs/operator guidance only.
2. Extend this repo with a stronger runtime mode while preserving the current
   official path.
3. Replace the runtime in a dedicated follow-up migration if the censorship
   resistance gain is worth the extra operational risk.
