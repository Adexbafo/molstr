# MolStr roadmap

## Milestone 1: done
- Multiple accounts, sign-out, keys in secure storage
- Notes, replies, likes, reposts, quotes, threads, observed counts
- Polls: create and vote (NIP-88), voter list
- Articles (NIP-23): create and open, plain text
- Follow and unfollow (NIP-02), with a safe list merge
- Profiles: NIP-05 badges, observed following and follower counts
- Foundations: themes, fonts, logo, wss-only relays, remote-image privacy toggle, diagnostics

## Milestone 2: done, gate open
- Emoji, image and video attachments
- Notifications tab
- Private messages (NIP-17): send, inbox, chat, relay lists (kind 10050)
- NIP-44 v2 vectors pass (4 vectors)
- Gate: Amethyst interop, both directions, correct sender

## Milestone 3: next
1. Global relay sets and relay health checks
2. Mute, block and report (store requirement, not built yet)
3. Wallet: NWC for Bitcoin, Monero handoff (Wallet tab is a placeholder)
4. Web of Trust, follow-based and ranked feed, spam filtering
5. Games showcase (Games tab is a placeholder)

## Milestone 4: later
- Tor (SOCKS5) with a user toggle
- Security and hardening review
- Store icons and listings

## Known limits

- Counts are observed on your selected relays, not network totals.
- Zap amounts come from the sender-signed request in each receipt. Payment itself is not yet verified against the recipient's Lightning server.
- Home shows recent notes from your relays. It is not follow-based yet.
- Image uploads skip the privacy notice that video uploads show.
- Relays see your IP address unless Tor is enabled.
- Messages: one partner per conversation, no groups. Relays see recipient tags and timing.
- Zap polls and Monero polls are parked: no ratified spec, and Monero votes can't be tallied publicly without giving up privacy.
