# Censorship Resistance Follow-Up

This repo now uses `mtg` as the production Telegram proxy runtime. The current
deployment target is:

1. Hetzner-hosted `mtg`
2. a public hostname such as `mtproxy.example.com`, plus direct-IP links for
   recovery
3. Cloudflare in DNS-only mode
4. TCP `443`
5. FakeTLS secrets generated for an operator-chosen front domain

## Why This Follow-Up Exists

The migration away from the official MTProxy server happened because the old
runtime and a long-lived static IP were too easy to burn. `mtg` gives this repo
a stronger FakeTLS-oriented runtime, but it still does not eliminate the need
for fast host replacement.

## Operating Rules

The operational assumptions for this repo are now:

1. The Hetzner host is disposable. If an IP is blocked, create a new host
   instead of trying to preserve the old one.
2. A direct-IP Telegram link is the primary recovery path. DNS-based links are
   optional convenience.
3. The FakeTLS front domain is an explicit operator choice and can be changed on
   later rotations.
4. Sponsored placement / adtag support is intentionally out of scope.

## Remaining Follow-Up

Further work should focus on:

1. Better front-domain selection guidance for different regions / providers.
2. Faster ban recovery automation around DNS repointing and old-host cleanup.
3. Extra verification that the chosen front domains still work acceptably from
   the target networks.
